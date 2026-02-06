defmodule Oban.Web.Workflows.SidebarComponent do
  use Oban.Web, :html

  alias Oban.Web.SidebarComponents

  attr :workflows, :list
  attr :params, :map
  attr :csp_nonces, :map
  attr :width, :integer, default: 320

  def sidebar(assigns) do
    ~H"""
    <SidebarComponents.sidebar width={@width} csp_nonces={@csp_nonces}>
      <SidebarComponents.section name="states" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{state, count} <- states(@workflows)}
          name={state}
          active={active_filter?(@params, :states, state)}
          patch={patch_params(@params, :workflows, :states, state)}
          values={[count]}
        />
      </SidebarComponents.section>

      <SidebarComponents.section name="names" headers={~w(count)}>
        <SidebarComponents.filter_row
          :for={{name, count} <- names(@workflows)}
          name={name}
          active={active_filter?(@params, :names, name)}
          patch={patch_params(@params, :workflows, :names, name)}
          values={[count]}
        />
      </SidebarComponents.section>
    </SidebarComponents.sidebar>
    """
  end

  defp states(workflows) do
    workflows
    |> Enum.frequencies_by(& &1.state)
    |> Enum.sort_by(fn {state, _} -> state end)
  end

  defp names(workflows) do
    workflows
    |> Enum.reject(&is_nil(&1.name))
    |> Enum.frequencies_by(& &1.name)
    |> Enum.sort_by(fn {name, _} -> name end)
  end
end
