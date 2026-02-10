defmodule Oban.Web.Repo.WorkflowQueryTest do
  use Oban.Web.Case, async: true

  alias Oban.Config
  alias Oban.Web.WorkflowQuery

  @repo Oban.Web.Repo
  @conf Config.new(repo: @repo, engine: Oban.Engines.Basic)

  describe "all_workflows/2" do
    test "grouping jobs by workflow_id" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"})
      insert!(%{}, meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"})
      insert!(%{}, meta: %{workflow_id: Ecto.UUID.generate()})
      insert!(%{}, meta: %{unrelated: true})

      workflows = WorkflowQuery.all_workflows(%{}, @conf)

      assert length(workflows) == 2

      workflow = Enum.find(workflows, &(&1.id == wf_id))
      assert workflow.name == "my_pipeline"
      assert workflow.total_jobs == 2
    end

    test "computing aggregate state from job states" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "executing")

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert workflow.state == :executing
    end

    test "completed state when all jobs are completed" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert workflow.state == :completed
    end

    test "filtering by workflow ids" do
      wf_id_a = Ecto.UUID.generate()
      wf_id_b = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id_a})
      insert!(%{}, meta: %{workflow_id: wf_id_b})

      workflows = WorkflowQuery.all_workflows(%{ids: [wf_id_a]}, @conf)

      assert length(workflows) == 1
      assert hd(workflows).id == wf_id_a
    end

    test "filtering by workflow names" do
      insert!(%{}, meta: %{workflow_id: Ecto.UUID.generate(), workflow_name: "alpha"})
      insert!(%{}, meta: %{workflow_id: Ecto.UUID.generate(), workflow_name: "beta"})

      workflows = WorkflowQuery.all_workflows(%{names: ["alpha"]}, @conf)

      assert length(workflows) == 1
      assert hd(workflows).name == "alpha"
    end

    test "sorting by time" do
      now = DateTime.utc_now()

      wf_old = Ecto.UUID.generate()
      wf_new = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_old}, attempted_at: DateTime.add(now, -60))
      insert!(%{}, meta: %{workflow_id: wf_new}, attempted_at: now)

      workflows =
        WorkflowQuery.all_workflows(%{sort_by: "time", sort_dir: "desc"}, @conf)

      ids = Enum.map(workflows, & &1.id)

      assert List.first(ids) == wf_new
    end

    test "limit returns the most recent workflows" do
      now = DateTime.utc_now()

      old_ids =
        for i <- 1..3 do
          id = Ecto.UUID.generate()
          insert!(%{}, meta: %{workflow_id: id}, attempted_at: DateTime.add(now, -3600 - i))
          id
        end

      new_ids =
        for i <- 1..2 do
          id = Ecto.UUID.generate()
          insert!(%{}, meta: %{workflow_id: id}, attempted_at: DateTime.add(now, -i))
          id
        end

      workflows = WorkflowQuery.all_workflows(%{limit: 2}, @conf)
      ids = Enum.map(workflows, & &1.id)

      assert length(ids) == 2
      assert Enum.all?(new_ids, &(&1 in ids))
      refute Enum.any?(old_ids, &(&1 in ids))
    end

    test "counting states correctly" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert workflow.counts.available == 2
      assert workflow.counts.completed == 1
      assert workflow.total_jobs == 3
    end

    test "populating inserted_at and scheduled_at timestamps" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id})

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert %DateTime{} = workflow.inserted_at
      assert %DateTime{} = workflow.scheduled_at
    end

    test "cancelled_at and discarded_at are nil when no jobs in those states" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert is_nil(workflow.cancelled_at)
      assert is_nil(workflow.discarded_at)
    end

    test "populating cancelled_at when cancelled jobs exist" do
      wf_id = Ecto.UUID.generate()

      insert!(%{},
        meta: %{workflow_id: wf_id},
        state: "cancelled",
        cancelled_at: DateTime.utc_now()
      )

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert %DateTime{} = workflow.cancelled_at
    end

    test "populating discarded_at when discarded jobs exist" do
      wf_id = Ecto.UUID.generate()

      insert!(%{},
        meta: %{workflow_id: wf_id},
        state: "discarded",
        discarded_at: DateTime.utc_now()
      )

      [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

      assert %DateTime{} = workflow.discarded_at
    end
  end

  describe "workflow_jobs/3" do
    test "returning jobs for a workflow" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id})
      insert!(%{}, meta: %{workflow_id: wf_id})
      insert!(%{}, meta: %{workflow_id: Ecto.UUID.generate()})

      jobs = WorkflowQuery.workflow_jobs(%{}, @conf, wf_id)

      assert length(jobs) == 2
    end

    test "filtering jobs by state" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")

      jobs = WorkflowQuery.workflow_jobs(%{states: ["available"]}, @conf, wf_id)

      assert length(jobs) == 1
      assert hd(jobs).state == "available"
    end

    test "filtering jobs by queue" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, queue: :alpha)
      insert!(%{}, meta: %{workflow_id: wf_id}, queue: :beta)

      jobs = WorkflowQuery.workflow_jobs(%{queues: ["alpha"]}, @conf, wf_id)

      assert length(jobs) == 1
      assert hd(jobs).queue == "alpha"
    end
  end

  describe "workflow_job_filters/2" do
    test "returning state counts for a workflow" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "available")
      insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")

      filters = WorkflowQuery.workflow_job_filters(@conf, wf_id)

      assert {"available", 2} in filters.states
      assert {"completed", 1} in filters.states
    end

    test "returning queue counts for a workflow" do
      wf_id = Ecto.UUID.generate()

      insert!(%{}, meta: %{workflow_id: wf_id}, queue: :alpha)
      insert!(%{}, meta: %{workflow_id: wf_id}, queue: :beta)
      insert!(%{}, meta: %{workflow_id: wf_id}, queue: :beta)

      filters = WorkflowQuery.workflow_job_filters(@conf, wf_id)

      assert {"alpha", 1} in filters.queues
      assert {"beta", 2} in filters.queues
    end
  end

  describe "parse/1" do
    import WorkflowQuery, only: [parse: 1]

    test "parsing id and name qualifiers" do
      assert %{ids: ["abc-123"]} = parse("ids:abc-123")
      assert %{ids: ["a", "b"]} = parse("ids:a,b")
      assert %{names: ["pipeline"]} = parse("names:pipeline")
      assert %{names: ["alpha", "beta"]} = parse("names:alpha,beta")
    end
  end

  defp insert!(args, opts) do
    {meta, opts} = Keyword.pop(opts, :meta, %{})
    {state, opts} = Keyword.pop(opts, :state, "available")
    {attempted_at, opts} = Keyword.pop(opts, :attempted_at)
    {cancelled_at, opts} = Keyword.pop(opts, :cancelled_at)
    {discarded_at, opts} = Keyword.pop(opts, :discarded_at)

    opts =
      opts
      |> Keyword.put_new(:queue, :default)
      |> Keyword.put_new(:worker, FakeWorker)

    args
    |> Map.new()
    |> Oban.Job.new(opts)
    |> Ecto.Changeset.put_change(:meta, meta)
    |> Ecto.Changeset.put_change(:state, state)
    |> maybe_put_change(:attempted_at, attempted_at)
    |> maybe_put_change(:cancelled_at, cancelled_at)
    |> maybe_put_change(:discarded_at, discarded_at)
    |> @repo.insert!()
  end

  defp maybe_put_change(cs, _field, nil), do: cs
  defp maybe_put_change(cs, field, value), do: Ecto.Changeset.put_change(cs, field, value)
end
