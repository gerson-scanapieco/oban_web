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

  @terminal_states [:completed, :cancelled, :discarded]

  @doc """
  Compute an aggregate workflow state from job state counts.

  Mirrors the logic from `Oban.Pro.Workflow.expand_status/3`:
  - Any non-terminal jobs → :executing
  - Any cancelled (all terminal) → :cancelled
  - Any discarded (all terminal) → :discarded
  - All completed → :completed
  """
  def aggregate_state(counts) do
    terminal = Enum.sum(for state <- @terminal_states, do: Map.get(counts, state, 0))
    total = counts |> Map.values() |> Enum.sum()

    cond do
      terminal < total -> :executing
      Map.get(counts, :cancelled, 0) > 0 -> :cancelled
      Map.get(counts, :discarded, 0) > 0 -> :discarded
      true -> :completed
    end
  end
end
