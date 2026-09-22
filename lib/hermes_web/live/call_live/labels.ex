defmodule HermesWeb.CallLive.Labels do
  @moduledoc """
  German labels for call results, attempt outcomes and live call states.
  """

  @results %{
    bridged: "Vermittelt",
    announced: "Ansage",
    all_busy: "Alle im Gespräch",
    rejected: "Abgewiesen",
    paused: "Pausiert",
    abandoned: "Aufgelegt",
    failed: "Fehler"
  }

  @result_classes %{
    bridged: "badge-success",
    announced: "badge-warning",
    all_busy: "badge-warning",
    rejected: "badge-ghost",
    paused: "badge-warning",
    abandoned: "badge-ghost",
    failed: "badge-error"
  }

  @outcomes %{
    confirmed: "angenommen",
    passed: "weitergegeben",
    rejected_all: "abgewiesen",
    no_confirmation: "keine Taste",
    busy: "besetzt",
    no_answer: "keine Antwort",
    rejected: "abgelehnt",
    failed: "Fehler"
  }

  @outcome_classes %{
    confirmed: "badge-success",
    passed: "badge-info",
    rejected_all: "badge-ghost",
    no_confirmation: "badge-warning",
    busy: "badge-ghost",
    no_answer: "badge-ghost",
    rejected: "badge-ghost",
    failed: "badge-error"
  }

  @states %{
    starting: "wird angenommen",
    resolving: "sucht Dienst",
    dialing: "ruft an",
    confirming: "wartet auf Bestätigung",
    bridged: "verbunden",
    announcing: "Ansage läuft",
    done: "wird beendet"
  }

  def result(result), do: Map.get(@results, result, to_string(result))
  def result_class(result), do: Map.get(@result_classes, result, "badge-ghost")
  def outcome(outcome), do: Map.get(@outcomes, outcome, to_string(outcome))
  def outcome_class(outcome), do: Map.get(@outcome_classes, outcome, "badge-ghost")
  def state(state), do: Map.get(@states, state, to_string(state))
end
