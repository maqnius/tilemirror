defmodule Tilemirror.FilterHostPlug do
  import Plug.Conn
  @behaviour Plug

  def init(%{allowed_hosts: allowed_hosts} = options) do
    %{options | allowed_hosts: MapSet.new(allowed_hosts)}
  end

  def call(
        conn,
        %{allowed_hosts: allowed_hosts}
      ) do
    if MapSet.member?(allowed_hosts, conn.host) do
      conn
    else
      send_resp(conn, 401, "Wrong host #{conn.host}") |> halt()
    end
  end
end

defmodule Tilemirror.Router do
  use Plug.Router
  require Logger

  plug(Tilemirror.FilterHostPlug, %{allowed_hosts: ["127.0.0.1", "hevenerfeld.de"]})
  plug(:match)
  plug(:dispatch)
  @supported_formats ~w(png webp)

  get("/_tile/:z/:x/:y_fmt") do
    with {:ok, z_int} <- parse_int(z),
         {:ok, x_int} <- parse_int(x),
         {:ok, y_int, format} <- parse_tile_params(y_fmt),
         true <- format in @supported_formats do
      case TileCache.get_tile(z_int, x_int, y_int, format) do
        {:ok, tile_data} ->
          conn
          |> put_resp_header("cache-control", "max-age=31536000")
          |> put_resp_content_type("image/#{format}")
          |> send_resp(200, tile_data)

        {:error, :out_of_bounds} ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(400, "Error: Out ouf allowed bounds")

        {:error, reason} ->
          Logger.error(reason)

          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(500, "Error: #{inspect(reason)}")
      end
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  get _ do
    send_resp(conn, 404, "not found")
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {int, ""} when int >= 0 -> {:ok, int}
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_tile_params(y_fmt) do
    case String.split(y_fmt, ".") do
      [y, format] ->
        case parse_int(y) do
          {:ok, y_int} -> {:ok, y_int, format}
          _ -> {:error, :invalid_params}
        end

      _ ->
        {:error, :invalid_format}
    end
  end
end

defmodule BBoxCalc do
  def ranges(bbox, min_zoom, max_zoom) do
    min_zoom..max_zoom
    |> Enum.map(fn z -> {z, ranges_for_zoom(bbox, z)} end)
    |> Map.new()
  end

  defp ranges_for_zoom(bbox, z) do
    {min_x, min_y} = latlon_to_tile(bbox.max_lat, bbox.min_lon, z)
    {max_x, max_y} = latlon_to_tile(bbox.min_lat, bbox.max_lon, z)

    %{
      x: min_x..max_x,
      y: min_y..max_y
    }
  end

  defp latlon_to_tile(lat, lon, z) do
    n = :math.pow(2, z)

    x =
      ((lon + 180.0) / 360.0 * n)
      |> floor()
      |> clamp(0, trunc(n - 1))

    lat_rad = deg2rad(lat)

    y =
      ((1.0 - :math.log(:math.tan(lat_rad) + 1.0 / :math.cos(lat_rad)) / :math.pi()) / 2.0 * n)
      |> floor()
      |> clamp(0, trunc(n - 1))

    {x, y}
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180.0

  defp clamp(v, min, _max) when v < min, do: min
  defp clamp(v, _min, max) when v > max, do: max
  defp clamp(v, _min, _max), do: v
end

defmodule TileCache do
  @moduledoc """
  A simple file system cache for map tiles from OpenStreetMap.
  """

  @cache_dir "tile_cache"
  @upstream_url "https://api.maptiler.com/maps/openstreetmap"

  # https://norbertrenner.de/osm/bbox.html
  # restrict served tiles to bounding box
  @bbox %{
    min_lat: 51.055,
    max_lat: 51.943,
    min_lon: 6.205,
    max_lon: 8.012
  }

  @min_zoom 0
  @max_zoom 18

  @allowed_tiles BBoxCalc.ranges(@bbox, @min_zoom, @max_zoom)

  defp api_key(), do: Application.fetch_env!(:tilemirror, :api_key)

  @doc """
  Gets a tile, either from cache or by fetching from upstream.
  Returns {:ok, binary} or {:error, reason}
  """
  def get_tile(z, x, y, format) do
    if allowed?(z, x, y) do
      cache_path = tile_path(z, x, y, format)

      case File.read(cache_path) do
        {:ok, data} ->
          {:ok, data}

        {:error, :enoent} ->
          fetch_and_cache_tile(z, x, y, format, cache_path)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :out_of_bounds}
    end
  end

  defp allowed?(z, x, y) do
    case @allowed_tiles[z] do
      %{x: xr, y: yr} -> x in xr and y in yr
      nil -> false
    end
  end

  defp fetch_and_cache_tile(z, x, y, format, cache_path) do
    url = "#{@upstream_url}/#{z}/#{x}/#{y}.#{format}?key=#{api_key()}"

    case :httpc.request(:get, {String.to_charlist(url), []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        cache_path |> Path.dirname() |> File.mkdir_p!()
        File.write!(cache_path, body)
        {:ok, body}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tile_path(z, x, y, format) do
    Path.join([@cache_dir, "#{z}", "#{x}", "#{y}.#{format}"])
  end

  @doc """
  Clears the entire tile cache.
  """
  def clear_cache do
    File.rm_rf(@cache_dir)
  end
end
