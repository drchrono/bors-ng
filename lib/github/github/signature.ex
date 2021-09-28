require Logger

defmodule BorsNG.GitHub.Signature do
  @moduledoc """
  Provides the ability to sign commits using gpg2.
  """

  @type tcommit_no_ts :: %{
          parents: [binary],
          tree: binary,
          message: binary,
          author: %{name: binary, email: binary},
          committer: %{name: binary, email: binary}
        }

  @type tcommit :: %{
          parents: [binary],
          tree: binary,
          message: binary,
          author: %{name: binary, email: binary, date: binary},
          committer: %{name: binary, email: binary, date: binary}
        }

  @type tcommit_sig :: %{
          parents: [binary],
          tree: binary,
          message: binary,
          author: %{name: binary, email: binary, date: binary},
          committer: %{name: binary, email: binary, date: binary},
          signature: binary
        }

  @spec add_timestamp(tcommit_no_ts, DateTime.t()) :: tcommit
  def add_timestamp(commit, dt) do
    ts = DateTime.to_iso8601(dt)

    commit
    |> Map.put(:author, Map.put(commit[:author], :date, ts))
    |> Map.put(:committer, Map.put(commit[:committer], :date, ts))
  end

  @spec format_commit(tcommit) :: binary
  def format_commit(commit) do
    {:ok, author_date, _} = DateTime.from_iso8601(commit[:author][:date])
    author_ts = DateTime.to_unix(author_date, :second) |> Integer.to_string()
    {:ok, committer_date, _} = DateTime.from_iso8601(commit[:committer][:date])
    committer_ts = DateTime.to_unix(committer_date, :second) |> Integer.to_string()

    gpg_sig =
      case Map.fetch(commit, :signature) do
        {:ok, sig} ->
          lines =
            String.split(sig, "\n")
            |> Enum.intersperse("\n ")
            |> Enum.to_list()

          ["gpgsig ", lines, "\n"]

        :error ->
          []
      end

    IO.iodata_to_binary([
      ["tree ", commit[:tree], "\n"],
      Enum.map(commit[:parents], fn parent -> ["parent ", parent, "\n"] end),
      [
        "author ",
        commit[:author][:name],
        " <",
        commit[:author][:email],
        "> ",
        author_ts,
        " +0000\n"
      ],
      [
        "committer ",
        commit[:committer][:name],
        " <",
        commit[:committer][:email],
        "> ",
        committer_ts,
        " +0000\n"
      ],
      gpg_sig,
      "\n",
      commit[:message]
    ])
  end

  @spec sign!(tcommit, binary) :: tcommit_sig
  def sign!(commit, key_id) do
    Logger.info("Signing commit #{inspect(commit)} with key #{inspect(key_id)}")

    path = System.find_executable("gpg")

    if is_nil(path) do
      throw(:missing_gpg)
    end

    commit_to_sign = format_commit(commit)
    Logger.debug("Commit to sign: #{inspect(commit_to_sign)}")

    tmp_dir = System.tmp_dir!()
    tmp_filename = Path.join(tmp_dir, "bors_commit_signing.#{commit[:tree]}.txt")
    sig_filename = Path.join(tmp_dir, "bors_commit_signing.#{commit[:tree]}.txt.asc")

    try do
      _ = File.rm(sig_filename)
      File.write!(tmp_filename, commit_to_sign, [:write, :binary, :sync])

      args = [
        "--batch",
        "--with-colons",
        "--status-fd",
        "2",
        "--armor",
        "--local-user",
        key_id,
        "--detach-sign",
        tmp_filename
      ]

      Logger.debug("Calling #{path} #{Enum.join(args, " ")}")
      {output, 0} = System.cmd(path, args)
      Logger.debug("Output from gpg: #{inspect(output)}")
      sig = File.read!(sig_filename)
      Map.put(commit, :signature, sig)
    after
      _ = File.rm(tmp_filename)
      _ = File.rm(sig_filename)
    end
  end
end
