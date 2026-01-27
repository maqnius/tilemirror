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

defmodule TileCache do
  @moduledoc """
  A simple file system cache for map tiles from OpenStreetMap.
  """

  @cache_dir "tile_cache"
  @upstream_url "https://api.maptiler.com/maps/openstreetmap"

  defp api_key(), do: Application.fetch_env!(:tilemirror, :api_key)

  @doc """
  Gets a tile, either from cache or by fetching from upstream.
  Returns {:ok, binary} or {:error, reason}
  """
  def get_tile(z, x, y, format) do
    cache_path = tile_path(z, x, y, format)

    case File.read(cache_path) do
      {:ok, data} ->
        {:ok, data}

      {:error, :enoent} ->
        fetch_and_cache_tile(z, x, y, format, cache_path)

      {:error, reason} ->
        {:error, reason}
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
