for repo <- [Oban.Web.Repo, Oban.Web.SQLiteRepo, Oban.Web.MyXQLRepo] do
  defmodule Module.concat(repo, WorkflowQueryTest) do
    use Oban.Web.Case, async: true

    alias Oban.Config
    alias Oban.Web.WorkflowQuery

    @repo repo

    @engine (case repo do
               Oban.Web.MyXQLRepo -> Oban.Engines.Dolphin
               Oban.Web.Repo -> Oban.Engines.Basic
               Oban.Web.SQLiteRepo -> Oban.Engines.Lite
             end)

    @conf Config.new(repo: @repo, engine: @engine)

    @moduletag myxql: repo == Oban.Web.MyXQLRepo
    @moduletag sqlite: repo == Oban.Web.SQLiteRepo

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

        assert workflow.state == "executing"
      end

      test "completed state when all jobs are completed" do
        wf_id = Ecto.UUID.generate()

        insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")
        insert!(%{}, meta: %{workflow_id: wf_id}, state: "completed")

        [workflow] = WorkflowQuery.all_workflows(%{ids: [wf_id]}, @conf)

        assert workflow.state == "completed"
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

        assert workflow.counts["available"] == 2
        assert workflow.counts["completed"] == 1
        assert workflow.total_jobs == 3
      end
    end

    describe "dep_jobs/3" do
      test "resolving dep names to job ids within a workflow" do
        wf_id = Ecto.UUID.generate()

        job_a = insert!(%{}, meta: %{workflow_id: wf_id, name: "step_a"})
        job_b = insert!(%{}, meta: %{workflow_id: wf_id, name: "step_b"})
        _other = insert!(%{}, meta: %{workflow_id: Ecto.UUID.generate(), name: "step_a"})

        result = WorkflowQuery.dep_jobs(@conf, wf_id, ["step_a", "step_b"])

        assert result == %{"step_a" => job_a.id, "step_b" => job_b.id}
      end

      test "returning partial results when some deps are missing" do
        wf_id = Ecto.UUID.generate()

        job_a = insert!(%{}, meta: %{workflow_id: wf_id, name: "step_a"})

        result = WorkflowQuery.dep_jobs(@conf, wf_id, ["step_a", "step_missing"])

        assert result == %{"step_a" => job_a.id}
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

      opts =
        opts
        |> Keyword.put_new(:queue, :default)
        |> Keyword.put_new(:worker, FakeWorker)

      args
      |> Map.new()
      |> Oban.Job.new(opts)
      |> Ecto.Changeset.put_change(:meta, meta)
      |> Ecto.Changeset.put_change(:state, state)
      |> then(fn cs ->
        if attempted_at do
          Ecto.Changeset.put_change(cs, :attempted_at, attempted_at)
        else
          cs
        end
      end)
      |> @repo.insert!()
    end
  end
end
