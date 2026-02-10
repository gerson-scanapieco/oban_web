defmodule Oban.Web.Jobs.DetailComponentTest do
  use Oban.Web.Case, async: true

  import Phoenix.LiveViewTest

  alias Oban.Config
  alias Oban.Web.Jobs.DetailComponent, as: Component

  @conf Config.new(repo: Oban.Web.Repo, engine: Oban.Engines.Basic)

  defmodule CustomResolver do
    @behaviour Oban.Web.Resolver

    @impl Oban.Web.Resolver
    def format_job_args(_job), do: "ARGS REDACTED"
  end

  setup do
    Process.put(:routing, :nowhere)

    :ok
  end

  test "restricting action buttons based on access" do
    job = %Oban.Job{id: 1, worker: "MyApp.Worker", args: %{}, state: "retryable"}

    html = render_component(Component, assigns(job, access: :read_only), router: Router)
    refute html =~ ~s(phx-click="cancel")

    html = render_component(Component, assigns(job, access: :all), router: Router)
    assert html =~ ~s(phx-click="cancel")
  end

  test "restricting actions based on job state" do
    job = %Oban.Job{id: 1, worker: "MyApp.Worker", args: %{}, state: "executing"}

    html = render_component(Component, assigns(job), router: Router)

    assert html =~ ~s(phx-click="cancel")
    refute html =~ ~s(phx-click="delete")
  end

  test "customizing args formatting with a resolver" do
    job = %Oban.Job{id: 1, worker: "MyApp.Worker", args: %{"secret" => "sauce"}}

    html = render_component(Component, assigns(job, resolver: CustomResolver), router: Router)

    assert html =~ "ARGS REDACTED"
  end

  test "rendering workflow section when job has workflow meta" do
    wf_id = Ecto.UUID.generate()

    job = %Oban.Job{
      id: 1,
      worker: "MyApp.Worker",
      args: %{},
      meta: %{"workflow_id" => wf_id, "workflow_name" => "my_pipeline"}
    }

    html = render_component(Component, assigns(job, conf: @conf), router: Router)

    assert html =~ "Workflow"
    assert html =~ "my_pipeline"
    assert html =~ wf_id
  end

  test "rendering workflow deps as links" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{"workflow_id" => wf_id, "name" => "step_a"})
    insert_job!(%{}, meta: %{"workflow_id" => wf_id, "name" => "step_b"})

    job = %Oban.Job{
      id: 99,
      worker: "MyApp.Worker",
      args: %{},
      meta: %{"workflow_id" => wf_id, "deps" => ["step_a", "step_b"]}
    }

    html = render_component(Component, assigns(job, conf: @conf), router: Router)

    assert html =~ "Workflow"
    assert html =~ "Dependencies"
    assert html =~ "step_a"
    assert html =~ "step_b"
  end

  test "not rendering workflow section without workflow meta" do
    job = %Oban.Job{id: 1, worker: "MyApp.Worker", args: %{}, meta: %{}}

    html = render_component(Component, assigns(job, conf: @conf), router: Router)

    refute html =~ "Workflow"
  end

  defp assigns(job, opts \\ []) do
    os_time = System.system_time(:second)

    [access: :all, id: :details, os_time: os_time, params: %{}, resolver: nil]
    |> Keyword.put(:job, job)
    |> Keyword.merge(opts)
  end
end
