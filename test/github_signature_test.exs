require Logger

defmodule BorsNG.GitHub.GitHubSignatureTest do
  use BorsNG.ConnCase
  alias BorsNG.GitHub.Signature

  test "can gpg-sign a commit" do
    key_id = Confex.fetch_env!(:bors, :test_gpg_key_id)
    cond do
      is_nil(System.find_executable("gpg")) ->
        Logger.info("Skipping GPG signing test because gpg is not installed")
      key_id == "" ->
        Logger.info("Skipping GPG signing test because test key was not set (see `config/test.exs`)")
      true ->
        date = DateTime.utc_now()
        commit_to_sign = %{
          tree: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          parents: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          author: %{
            name: "Author Name",
            email: "author@example.com",
            date: DateTime.to_iso8601(date),
          },
          committer: %{
            name: "Committer Name",
            email: "committer@example.com",
            date: DateTime.to_iso8601(date),
          },
          message: "Example commit"
        }

        commit_with_sig = Signature.sign!(commit_to_sign, key_id)
        raw_with_sig = Signature.format_commit(commit_with_sig)

        # Create a temporary git repo, insert the raw commit, and verify it with
        # `git-verify-commit`.
        git = System.find_executable("git")
        tmp_dir = Path.join(System.tmp_dir!(), "git-signature-test.#{Enum.random(10000..99999)}")
        :ok = File.mkdir!(tmp_dir)
        try do
          # create empty git repo
          Logger.debug("Creating temporary git repository at #{tmp_dir}")
          {_, 0} = System.cmd(git, ["init"], cd: tmp_dir, stderr_to_stdout: true)
          # insert raw commit object
          Logger.debug("Inserting raw commit object")
          raw_obj_path = Path.join(tmp_dir, "raw-commit.txt")
          :ok = File.write!(raw_obj_path, raw_with_sig, [:write, :binary, :sync])
          {raw_hash, 0} = System.cmd(
            git, ["hash-object", "-t", "commit", "-w", raw_obj_path],
            cd: tmp_dir, stderr_to_stdout: true
          )
          hash = String.trim(raw_hash)
          # verify commit
          Logger.debug("Verifying commit #{inspect hash}")
          {_, 0} = System.cmd(git, ["verify-commit", "--verbose", hash], cd: tmp_dir)
        after
          File.rm_rf!(tmp_dir)
        end
    end
  end
end
