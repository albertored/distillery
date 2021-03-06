defmodule Mix.Releases.Utils do
  @moduledoc false

  @doc """
  Loads a template from :distillery's `priv/templates` directory based on the provided name.
  Any parameters provided are configured as bindings for the template

  ## Example

      iex> {:ok, contents} = #{__MODULE__}.template("erl_script", [erts_vsn: "8.0"])
      ...> String.contains?(contents, "erts-8.0")
      true
  """
  @spec template(atom | String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, term}
  def template(name, params \\ []) do
    Application.app_dir(:distillery, Path.join("priv", "templates"))
    |> Path.join("#{name}.eex")
    |> template_path(params)
  end

  @doc """
  Loads a template from the provided path
  Any parameters provided are configured as bindings for the template

  ## Example
      iex> path = Path.join(["#{:code.priv_dir(:distillery)}", "templates", "erl_script.eex"])
      ...> {:ok, contents} = #{__MODULE__}.template_path(path, [erts_vsn: "8.0"])
      ...> String.contains?(contents, "erts-8.0")
      true
  """
  @spec template_path(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, term}
  def template_path(template_path, params \\ []) do
    {:ok, EEx.eval_file(template_path, params)}
  rescue
    e ->
      {:error, {:template, e}}
  end

  @doc """
  Writes an Elixir/Erlang term to the provided path
  """
  def write_term(path, term) do
    path = String.to_charlist(path)
    contents = :io_lib.fwrite('~p.\n', [term])

    case :file.write_file(path, contents, encoding: :utf8) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, {:write_terms, :file, reason}}
    end
  end

  @doc """
  Writes a collection of Elixir/Erlang terms to the provided path
  """
  def write_terms(path, terms) when is_list(terms) do
    contents =
      String.duplicate("~p.\n\n", Enum.count(terms))
      |> String.to_charlist()
      |> :io_lib.fwrite(Enum.reverse(terms))

    case :file.write_file('#{path}', contents, encoding: :utf8) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, {:write_terms, :file, reason}}
    end
  end

  @doc """
  Reads a file as Erlang terms
  """
  @spec read_terms(String.t()) :: {:ok, [term]} :: {:error, term}
  def read_terms(path) do
    case :file.consult(String.to_charlist(path)) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        {:error, {:read_terms, :file, reason}}
    end
  end

  @type write_all_template_spec :: {:template, atom | String.t(), Keyword.t()}
  @type write_all_pair ::
          {String.t(), binary}
          | {String.t(), binary, pos_integer}
          | {String.t(), write_all_template_spec}
          | {String.t(), write_all_template_spec, pos_integer}

  @doc """
  Given a list of tuples containing paths to write, either
  the content to write or a template specification for the content,
  and an optional octal permissions value; write a file to the given
  path, using the content provided, and if given, assign permissions
  to the written file.

  ## Examples

      write_all([{"path/to/file", <<"hello world">>}])
      
      write_all([{"path/to/file", {:template, :foo_template, [key: :val]}}])

      write_all([{"path/to/file", <<"hello world">>, Oo777}])
  """
  @spec write_all([write_all_pair]) :: :ok | {:error, term}
  def write_all([]), do: :ok

  def write_all([{path, {:template, tmpl, params}} | files]) do
    case template(tmpl, params) do
      {:ok, contents} ->
        write_all([{path, contents} | files])

      err ->
        err
    end
  end

  def write_all([{path, contents} | files]) do
    case File.write(path, contents) do
      :ok ->
        write_all(files)

      err ->
        err
    end
  end

  def write_all([{path, {:template, tmpl, params}, permissions} | files]) do
    case template(tmpl, params) do
      {:ok, contents} ->
        write_all([{path, contents, permissions} | files])

      err ->
        err
    end
  end

  def write_all([{path, contents, permissions} | files]) do
    with :ok <- File.write(path, contents),
         :ok <- File.chmod(path, permissions) do
      write_all(files)
    end
  end

  @doc """
  Determines the current ERTS version
  """
  @spec erts_version() :: String.t()
  def erts_version, do: "#{:erlang.system_info(:version)}"

  @doc """
  Verified that the ERTS path provided is the right one.
  If no ERTS path is specified it's fine. Distillery will work out
  the system ERTS
  """
  @spec validate_erts(String.t() | nil | boolean) :: :ok | {:error, [{:error, term}]}
  def validate_erts(path) when is_binary(path) do
    erts =
      case Path.join(path, "erts-*") |> Path.wildcard() |> Enum.count() do
        0 -> {:error, {:invalid_erts, :missing_directory}}
        1 -> :ok
        _ -> {:error, {:invalid_erts, :too_many}}
      end

    bin =
      if File.exists?(Path.join(path, "bin")) do
        :ok
      else
        {:error, {:invalid_erts, :missing_bin}}
      end

    lib =
      case File.exists?(Path.join(path, "lib")) do
        false -> {:error, {:invalid_erts, :missing_lib}}
        true -> :ok
      end

    errors =
      [erts, bin, lib]
      |> Enum.filter(fn x -> x != :ok end)
      |> Enum.map(fn {:error, _} = err -> err end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  def validate_erts(include_erts) when is_nil(include_erts) or is_boolean(include_erts), do: :ok

  @doc """
  Detects the version of ERTS in the given directory
  """
  @spec detect_erts_version(String.t()) :: {:ok, String.t()} | {:error, term}
  def detect_erts_version(path) when is_binary(path) do
    entries =
      path
      |> Path.expand()
      |> Path.join("erts-*")
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)

    case entries do
      [<<"erts-", vsn::binary>>] ->
        {:ok, vsn}

      _ ->
        {:error, {:invalid_erts, :cannot_determine_version}}
    end
  end

  @doc """
  Same as `insecure_mkdir_temp/0`, but raises on failure
  """
  @spec insecure_mkdir_temp!() :: String.t() | no_return
  def insecure_mkdir_temp!() do
    case insecure_mkdir_temp() do
      {:ok, dir} ->
        dir

      {:error, {:mkdir_temp, :file, reason}} ->
        raise "Failed to create temporary directory: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a temporary directory with a random name in a canonical
  temporary files directory of the current system
  (i.e. `/tmp` on *NIX or `./tmp` on Windows)

  Returns an ok tuple with the path of the temp directory, or an error
  tuple with the reason it failed.
  """
  @spec insecure_mkdir_temp() :: {:ok, String.t()} | {:error, term}
  def insecure_mkdir_temp() do
    :rand.seed(:exs64)
    unique_num = :rand.uniform(1_000_000_000)

    tmpdir_path =
      case :erlang.system_info(:system_architecture) do
        'win32' ->
          Path.join(["./tmp", ".tmp_dir#{unique_num}"])

        _ ->
          Path.join(["/tmp", ".tmp_dir#{unique_num}"])
      end

    case File.mkdir_p(tmpdir_path) do
      :ok ->
        {:ok, tmpdir_path}

      {:error, reason} ->
        {:error, {:mkdir_temp, :file, reason}}
    end
  end

  @doc """
  Deletes the given path, if it exists.
  """
  def remove_if_exists(path) do
    if File.exists?(path) do
      case File.rm_rf(path) do
        {:ok, _} ->
          :ok

        {:error, reason, file} ->
          {:error, {:assembler, :file, {reason, file}}}
      end
    else
      :ok
    end
  end

  @doc """
  Deletes the given path properly, depending on whether it is a symlink or not
  """
  def remove_symlink_or_dir!(path) do
    case File.exists?(path) do
      true ->
        File.rm_rf!(path)

      false ->
        if symlink?(path) do
          File.rm!(path)
        end
    end

    :ok
  rescue
    e in [File.Error] ->
      {:error, {:assembler, :file, {e.reason, e.path}}}
  end

  @doc """
  Returns true if the given path is a symlink, otherwise false
  """
  @spec symlink?(String.t()) :: boolean
  def symlink?(path) do
    case :file.read_link_info('#{path}') do
      {:ok, info} ->
        elem(info, 2) == :symlink

      _ ->
        false
    end
  end

  @doc """
  Given a path to a release output directory, return a list
  of release versions that are present.

  ## Example

      iex> app_dir = Path.join([File.cwd!, "test", "fixtures", "mock_app"])
      ...> output_dir = Path.join([app_dir, "rel", "mock_app"])
      ...> #{__MODULE__}.get_release_versions(output_dir)
      ["0.2.2", "0.2.1-1-d3adb3f", "0.2.1", "0.2.0", "0.1.0"]
  """
  @valid_version_pattern ~r/^\d+.*$/
  @spec get_release_versions(String.t()) :: list(String.t())
  def get_release_versions(output_dir) do
    releases_path = Path.join([output_dir, "releases"])

    if File.exists?(releases_path) do
      releases_path
      |> File.ls!()
      |> Enum.filter(&Regex.match?(@valid_version_pattern, &1))
      |> sort_versions
    else
      []
    end
  end

  @git_describe_pattern ~r/(?<ver>\d+\.\d+\.\d+)-(?<commits>\d+)-(?<sha>[A-Ga-g0-9]+)/
  @doc """
  Sort a list of version strings, in reverse order (i.e. latest version comes first)
  Tries to use semver version compare, but can fall back to regular string compare.
  It also parses git-describe generated version strings and handles ordering them
  correctly.

  ## Example

      iex> #{__MODULE__}.sort_versions(["1.0.2", "1.0.1", "1.0.9", "1.0.10"])
      ["1.0.10", "1.0.9", "1.0.2", "1.0.1"]

      iex> #{__MODULE__}.sort_versions(["0.0.1", "0.0.2", "0.0.1-2-a1d2g3f", "0.0.1-1-deadbeef"])
      ["0.0.2", "0.0.1-2-a1d2g3f", "0.0.1-1-deadbeef", "0.0.1"]
  """
  @spec sort_versions(list(String.t())) :: list(String.t())
  def sort_versions(versions) do
    versions
    |> Enum.map(fn ver ->
      # Special handling for git-describe versions
      compared =
        case Regex.named_captures(@git_describe_pattern, ver) do
          nil ->
            {:standard, ver, nil}

          %{"ver" => version, "commits" => n, "sha" => sha} ->
            {:describe, <<version::binary, ?+, n::binary, ?-, sha::binary>>, String.to_integer(n)}
        end

      {ver, compared}
    end)
    |> Enum.sort(fn {_, {v1type, v1str, v1_commits_since}},
                    {_, {v2type, v2str, v2_commits_since}} ->
      case {parse_version(v1str), parse_version(v2str)} do
        {{:semantic, v1}, {:semantic, v2}} ->
          case Version.compare(v1, v2) do
            :gt ->
              true

            :eq ->
              case {v1type, v2type} do
                # probably always false
                {:standard, :standard} ->
                  v1 > v2

                # v2 is an incremental version over v1
                {:standard, :describe} ->
                  false

                # v1 is an incremental version over v2
                {:describe, :standard} ->
                  true

                # need to parse out the bits
                {:describe, :describe} ->
                  v1_commits_since > v2_commits_since
              end

            :lt ->
              false
          end

        {{_, v1}, {_, v2}} ->
          v1 > v2
      end
    end)
    |> Enum.map(fn {v, _} -> v end)
  end

  defp parse_version(ver) do
    case Version.parse(ver) do
      {:ok, semver} ->
        {:semantic, semver}

      :error ->
        {:unsemantic, ver}
    end
  end

  # Determines if the given application directory is part of the Erlang installation
  @spec is_erts_lib?(String.t()) :: boolean
  @spec is_erts_lib?(String.t(), String.t()) :: boolean
  def is_erts_lib?(app_dir), do: is_erts_lib?(app_dir, "#{:code.lib_dir()}")
  def is_erts_lib?(app_dir, lib_dir), do: String.starts_with?(app_dir, lib_dir)

  @doc false
  @spec newline() :: String.t()
  def newline() do
    case :os.type() do
      {:win32, _} -> "\r\n"
      {:unix, _} -> "\n"
    end
  end
  
  @doc false
  def format_systools_warning(mod, warnings) do
    warning =
      mod.format_warning(warnings)
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map(fn e -> "    " <> e end)
      |> Enum.join("\n")
      |> String.trim_trailing()

    "#{warning}"
  end

  @doc false
  def format_systools_error(mod, errors) do
    error =
      mod.format_error(errors)
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map(fn e -> "    " <> e end)
      |> Enum.join("\n")
      |> String.trim_trailing()

    "#{error}"
  end
end
