defmodule Hermes.Speech do
  @moduledoc """
  Turns announcement texts into telephone-ready audio, using Piper (a local
  neural text-to-speech) and `sox` for resampling. Nothing leaves the host.

  Audio is produced when a text changes, never during a call: a call must not
  wait for a synthesizer.

  Without Piper installed (development machines, minimal images) `available?/0`
  returns false and the shipped default announcements stay in place.
  """

  require Logger

  # What the phone network uses anyway.
  @sample_rate 8000
  @channels 1
  @bits 16

  @doc """
  Name of the voice in use, e.g. `"de_DE-thorsten-medium"`, or `"none"` when
  no speech synthesis is installed. It is part of the marker next to every
  announcement, so switching the voice regenerates them.
  """
  def voice_name do
    case voice() do
      "" -> "none"
      path -> path |> Path.basename() |> String.replace_suffix(".onnx", "")
    end
  end

  @doc "Whether Piper and sox are available in this installation."
  def available? do
    File.exists?(piper_bin()) and File.exists?(voice()) and System.find_executable("sox") != nil
  end

  @doc """
  Writes `text` as a WAV file (8 kHz, 16 bit, mono) to `path`.

  The file is written atomically: Asterisk must never read a half-written
  announcement.
  """
  @spec synthesize(String.t(), Path.t()) :: :ok | {:error, term()}
  def synthesize(text, path) do
    text = String.trim(text)

    cond do
      text == "" -> {:error, :empty_text}
      not available?() -> {:error, :unavailable}
      true -> do_synthesize(text, path)
    end
  end

  @doc """
  Converts an uploaded audio file into the same telephone format.
  """
  @spec convert(Path.t(), Path.t()) :: :ok | {:error, term()}
  def convert(source, path) do
    if System.find_executable("sox") do
      with_temp_file(&convert_into(source, &1, path))
    else
      {:error, :unavailable}
    end
  end

  defp convert_into(source, temp, path) do
    with :ok <- sox(source, temp), do: install(temp, path)
  end

  defp do_synthesize(text, path) do
    with_temp_file(fn temp ->
      raw = temp <> ".raw.wav"

      try do
        with :ok <- piper(text, raw),
             :ok <- sox(raw, temp) do
          install(temp, path)
        end
      after
        File.rm(raw)
      end
    end)
  end

  # Piper reads the text from stdin. It is handed over through the environment
  # rather than the command line, so it never shows up in the process list.
  defp piper(text, output) do
    command =
      "printf '%s' \"$HERMES_TTS_TEXT\" | #{shell_quote(piper_bin())} " <>
        "--model #{shell_quote(voice())} --output_file #{shell_quote(output)}"

    case System.cmd("sh", ["-c", command],
           stderr_to_stdout: true,
           env: [{"HERMES_TTS_TEXT", text}]
         ) do
      {_output, 0} -> :ok
      {output, status} -> fail("piper", status, output)
    end
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp sox(source, output) do
    args = [
      source,
      "-r",
      Integer.to_string(@sample_rate),
      "-c",
      Integer.to_string(@channels),
      "-b",
      Integer.to_string(@bits),
      output
    ]

    case System.cmd("sox", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> fail("sox", status, output)
    end
  end

  # Move into place in one step, so a call never picks up a partial file.
  defp install(temp, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)), do: move(temp, path)
  end

  defp move(temp, path) do
    case File.rename(temp, path) do
      :ok -> :ok
      # Different file systems cannot be renamed across.
      {:error, :exdev} -> copy(temp, path)
      error -> error
    end
  end

  defp copy(temp, path) do
    with {:ok, _bytes} <- File.copy(temp, path), do: :ok
  end

  defp with_temp_file(fun) do
    temp =
      Path.join(
        System.tmp_dir!(),
        "hermes-speech-#{System.unique_integer([:positive])}.wav"
      )

    try do
      fun.(temp)
    after
      File.rm(temp)
    end
  end

  defp fail(tool, status, output) do
    Logger.warning("#{tool} failed (#{status}): #{String.slice(output, 0, 500)}")
    {:error, {tool, status}}
  end

  defp piper_bin, do: Application.get_env(:hermes, :piper_bin) || System.get_env("PIPER_BIN", "")
  defp voice, do: Application.get_env(:hermes, :piper_voice) || System.get_env("PIPER_VOICE", "")
end
