defmodule Oban.Web.WorkflowsPage do
  @behaviour Oban.Web.Page

  use Oban.Web, :live_component

  alias Oban.Web.Workflows.{SidebarComponent, TableComponent}
  alias Oban.Web.{Page, SearchComponent, SortComponent, WorkflowQuery}

  @known_params ~w(ids names states sort_by sort_dir limit)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="workflows-page" class="w-full flex flex-col my-6 md:flex-row">
      <SidebarComponent.sidebar
        workflows={@workflows}
        params={without_defaults(@params, @default_params)}
        width={@sidebar_width}
        csp_nonces={@csp_nonces}
      />

      <div class="flex-grow">
        <div class="bg-white dark:bg-gray-900 rounded-md shadow-lg">
          <div class="flex items-start pr-3 py-3 border-b border-gray-200 dark:border-gray-700">
            <div id="workflows-header" class="h-10 pr-12 flex-none flex items-center">
              <div class="flex-none flex items-center pl-12">
                <h2 class="text-lg dark:text-gray-200 leading-4 font-bold">Workflows</h2>
              </div>
            </div>

            <.live_component
              conf={@conf}
              id="search"
              module={SearchComponent}
              page={:workflows}
              params={without_defaults(@params, @default_params)}
              queryable={WorkflowQuery}
              resolver={@resolver}
            />

            <div class="pl-3 ml-auto">
              <SortComponent.select
                id="workflows-sort"
                by={~w(time name total)}
                page={:workflows}
                params={@params}
              />
            </div>
          </div>

          <.live_component
            id="workflows-table"
            module={TableComponent}
            params={@params}
            workflows={@workflows}
          />
        </div>
      </div>
    </div>
    """
  end

  @keep_on_mount ~w(default_params params workflows)a

  @impl Page
  def handle_mount(socket) do
    default = fn -> %{limit: 20, sort_by: "time", sort_dir: "desc"} end

    assigns =
      Map.drop(socket.assigns, @keep_on_mount)

    %{socket | assigns: assigns}
    |> assign_new(:default_params, default)
    |> assign_new(:params, default)
    |> assign_new(:workflows, fn -> [] end)
  end

  @impl Page
  def handle_refresh(socket) do
    conf = socket.assigns.conf
    params = socket.assigns.params

    workflows =
      params
      |> WorkflowQuery.all_workflows(conf)
      |> filter_by_states(params)

    assign(socket, workflows: workflows)
  end

  defp filter_by_states(workflows, %{states: states}) when is_list(states) and states != [] do
    Enum.filter(workflows, &(&1.state in states))
  end

  defp filter_by_states(workflows, _params), do: workflows

  @impl Page
  def handle_params(params, _uri, socket) do
    params =
      params
      |> Map.take(@known_params)
      |> decode_params()

    socket =
      socket
      |> assign(page_title: page_title("Workflows"))
      |> assign(params: Map.merge(socket.assigns.default_params, params))
      |> handle_refresh()

    {:noreply, socket}
  end

  @impl Page
  def handle_info({:params, :limit, inc}, socket) when is_integer(inc) do
    params =
      socket.assigns.params
      |> Map.update!(:limit, &to_string(&1 + inc))
      |> without_defaults(socket.assigns.default_params)

    {:noreply, push_patch(socket, to: oban_path(:workflows, params), replace: true)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
