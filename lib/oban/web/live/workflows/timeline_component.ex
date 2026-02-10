defmodule Oban.Web.Workflows.TimelineComponent do
  @moduledoc false

  use Phoenix.Component

  alias Oban.Web.Components.Icons
  alias Oban.Web.Timing

  @empty_time "—"

  @state_to_timestamp %{
    "inserted" => :inserted_at,
    "scheduled" => :scheduled_at,
    "executing" => :attempted_at,
    "cancelled" => :cancelled_at,
    "discarded" => :discarded_at
  }

  def render(assigns) do
    ~H"""
    <div
      id={"wf-timeline-for-#{@state}"}
      class="w-1/4 flex flex-col"
      data-title={timestamp_title(@state, @workflow)}
      phx-hook="Tippy"
    >
      <span class={"flex self-center justify-center items-center h-16 w-16 transition-colors duration-200 rounded-full #{timeline_class(@state, @workflow)}"}>
        <%= if timeline_icon(@state, @workflow) == :checkmark do %>
          <Icons.check class="w-12 h-12" />
        <% end %>
        <%= if timeline_icon(@state, @workflow) == :spinner do %>
          <svg class="h-12 w-12 animate-spin" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M10 1a.9.9 0 110 1.8 7.2 7.2 0 107.2 7.2.9.9 0 111.8 0 9 9 0 11-9-9z"
              fill-rule="nonzero"
            />
          </svg>
        <% end %>
      </span>
      <span class="block text-sm text-center font-semibold mt-2">
        {timestamp_name(@state, @workflow)}
      </span>
      <span class="block text-sm text-center tabular">
        {timeline_time(@state, @workflow, @os_time)}
      </span>
    </div>
    """
  end

  # Helpers

  defp timestamp_title(state, workflow) do
    timestamp = Map.get(workflow, Map.get(@state_to_timestamp, state))

    label =
      case state do
        "inserted" -> "Inserted At"
        "scheduled" -> "Scheduled At"
        "executing" -> "Attempted At"
        "cancelled" -> "Cancelled At"
        "discarded" -> "Discarded At"
      end

    "#{label}: #{truncate_sec(timestamp)}"
  end

  defp timeline_class(state, workflow) do
    case absolute_state(state, workflow) do
      :finished -> "bg-green-500 text-white"
      :started -> "bg-yellow-400 text-white"
      :unstarted -> "bg-gray-100 text-white dark:bg-black dark:bg-opacity-25"
    end
  end

  defp timeline_icon(state, workflow) do
    case absolute_state(state, workflow) do
      :finished -> :checkmark
      :started -> :spinner
      :unstarted -> nil
    end
  end

  defp timestamp_name(state, workflow) do
    case {state, workflow.state} do
      {"executing", :executing} ->
        "Executing"

      {"executing", :completed} ->
        "Completed"

      {"executing", _} ->
        "Executing"

      _ ->
        String.capitalize(state)
    end
  end

  defp timeline_time(state, workflow, os_time) do
    for_state = Map.get(@state_to_timestamp, state)
    timestamp = Map.get(workflow, for_state)
    now = DateTime.from_unix!(os_time)

    case {state, workflow.state, timestamp} do
      {_, _, nil} ->
        @empty_time

      {"executing", :executing, at} ->
        at
        |> DateTime.diff(now)
        |> Timing.to_duration()

      {_, _, at} ->
        at
        |> DateTime.diff(now)
        |> Timing.to_words()
    end
  end

  defp absolute_state("inserted", _workflow), do: :finished
  defp absolute_state("scheduled", _workflow), do: :finished

  defp absolute_state("executing", workflow) do
    case workflow.state do
      :completed -> :finished
      :executing -> :started
      _ -> :unstarted
    end
  end

  defp absolute_state("cancelled", workflow) do
    if workflow.state == :cancelled, do: :finished, else: :unstarted
  end

  defp absolute_state("discarded", workflow) do
    if workflow.state == :discarded, do: :finished, else: :unstarted
  end

  defp truncate_sec(nil), do: @empty_time
  defp truncate_sec(datetime), do: NaiveDateTime.truncate(datetime, :second)
end
