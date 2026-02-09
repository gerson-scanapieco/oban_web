defmodule Oban.Web.Workflows.SidebarComponent do
  use Oban.Web, :html

  alias Oban.Web.SidebarComponents

  @all_states ~w(executing available scheduled retryable cancelled discarded completed)

  attr :state_counts, :map
  attr :params, :map
  attr :active_states, :any
  attr :csp_nonces, :map
  attr :width, :integer, default: 320

  def sidebar(assigns) do
    ~H"""
    <SidebarComponents.sidebar width={@width} csp_nonces={@csp_nonces}>
      <SidebarComponents.section name="states" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{state, count} <- states(@state_counts)}
          name={state}
          active={state_active?(@active_states, state)}
          exclusive={true}
          patch={state_patch(@params, @active_states, state)}
          values={[count]}
        />
      </SidebarComponents.section>
    </SidebarComponents.sidebar>
    """
  end

  defp states(counts) do
    Enum.map(@all_states, fn state -> {state, Map.get(counts, state, 0)} end)
  end

  defp state_active?(active, state) do
    active == state or active == [state]
  end

  defp state_patch(params, active, state) do
    params =
      if state_active?(active, state) do
        Map.delete(params, :states)
      else
        Map.put(params, :states, state)
      end

    oban_path(:workflows, params)
  end
end
