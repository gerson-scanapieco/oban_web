defmodule Oban.Web.Workflows.DetailSidebarComponent do
  use Oban.Web, :html

  alias Oban.Web.SidebarComponents

  attr :workflow_id, :string
  attr :params, :map
  attr :states, :list
  attr :queues, :list
  attr :nodes, :list
  attr :csp_nonces, :map
  attr :width, :integer, default: 320

  def sidebar(assigns) do
    ~H"""
    <SidebarComponents.sidebar width={@width} csp_nonces={@csp_nonces}>
      <SidebarComponents.section name="states" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{state, count} <- @states}
          name={state}
          active={active_filter?(@params, :states, state)}
          patch={detail_patch_params(@params, @workflow_id, :states, state)}
          values={[count]}
        />
      </SidebarComponents.section>

      <SidebarComponents.section name="queues" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{queue, count} <- @queues}
          name={queue}
          active={active_filter?(@params, :queues, queue)}
          patch={detail_patch_params(@params, @workflow_id, :queues, queue)}
          values={[count]}
        />
      </SidebarComponents.section>

      <SidebarComponents.section name="nodes" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{node, count} <- @nodes}
          name={node}
          active={active_filter?(@params, :nodes, node)}
          patch={detail_patch_params(@params, @workflow_id, :nodes, node)}
          values={[count]}
        />
      </SidebarComponents.section>
    </SidebarComponents.sidebar>
    """
  end

  defp detail_patch_params(params, workflow_id, key, value) do
    value = to_string(value)
    param_value = params[key]

    params =
      cond do
        value == param_value or [value] == param_value ->
          Map.delete(params, key)

        is_list(param_value) and value in param_value ->
          Map.put(params, key, List.delete(param_value, value))

        is_list(param_value) ->
          Map.put(params, key, [value | param_value])

        true ->
          Map.put(params, key, value)
      end

    oban_path([:workflows, workflow_id], params)
  end
end
