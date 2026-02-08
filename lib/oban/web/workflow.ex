defmodule Oban.Web.Workflow do
  @moduledoc false

  defstruct [
    :id,
    :name,
    :state,
    :counts,
    :started_at,
    :total_jobs,
    :inserted_at,
    :scheduled_at,
    :attempted_at,
    :cancelled_at,
    :completed_at,
    :discarded_at
  ]

  @doc """
  Compute an aggregate workflow state from job state counts.

  Priority order:
  - Any executing → "executing"
  - Any retryable (none executing) → "retryable"
  - Any available/scheduled (none executing/retryable) → "available"
  - Any cancelled (none active) → "cancelled"
  - Any discarded (none active) → "discarded"
  - All completed → "completed"
  """
  def aggregate_state(counts) do
    cond do
      count(counts, "executing") > 0 -> "executing"
      count(counts, "retryable") > 0 -> "retryable"
      count(counts, "available") > 0 or count(counts, "scheduled") > 0 -> "available"
      count(counts, "cancelled") > 0 -> "cancelled"
      count(counts, "discarded") > 0 -> "discarded"
      true -> "completed"
    end
  end

  defp count(counts, state), do: Map.get(counts, state, 0)
end
