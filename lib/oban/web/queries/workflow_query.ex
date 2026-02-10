defmodule Oban.Web.WorkflowQuery do
  @moduledoc false

  import Ecto.Query

  alias Oban.{Job, Repo}
  alias Oban.Web.{Search, Workflow}

  @defaults %{
    limit: 20,
    sort_by: "time",
    sort_dir: "desc"
  }

  @suggest_qualifier [
    {"ids:", "one or more workflow ids", "ids:abc-123"},
    {"names:", "workflow name", "names:data_pipeline"}
  ]

  @known_qualifiers MapSet.new(@suggest_qualifier, fn {qualifier, _, _} -> qualifier end)

  # Searching

  def filterable, do: ~w(ids names)a

  def parse(terms) when is_binary(terms) do
    Search.parse(terms, &parse_term/1)
  end

  def suggest(terms, _conf, _opts \\ []) do
    terms
    |> String.split(~r/\s+(?=([^\"]*\"[^\"]*\")*[^\"]*$)/)
    |> List.last()
    |> to_string()
    |> case do
      "" ->
        @suggest_qualifier

      last ->
        case String.split(last, ":", parts: 2) do
          [frag] -> suggest_static(frag, @suggest_qualifier)
          _ -> []
        end
    end
  end

  defp suggest_static(fragment, possibilities) do
    for {field, _, _} = suggest <- possibilities,
        String.starts_with?(field, fragment),
        do: suggest
  end

  def append(terms, choice) do
    Search.append(terms, choice, @known_qualifiers)
  end

  def complete(terms, conf) do
    case suggest(terms, conf) do
      [] ->
        terms

      [{match, _, _} | _] ->
        append(terms, match)
    end
  end

  defp parse_term("ids:" <> ids) do
    {:ids, String.split(ids, ",")}
  end

  defp parse_term("names:" <> names) do
    {:names, String.split(names, ",")}
  end

  defp parse_term(_term), do: {:none, ""}

  # Querying

  def dep_jobs(conf, workflow_id, dep_names) when is_list(dep_names) do
    conf.name
    |> Oban.Pro.Workflow.all_jobs(workflow_id, names: dep_names)
    |> Map.new(fn %Job{id: id, meta: meta} -> {meta["name"], id} end)
  end

  def all_workflows(params, conf, _opts \\ []) do
    params = params_with_defaults(params)

    query =
      base_query()
      |> filter_ids(params)
      |> filter_names(params)
      |> order_query(params)
      |> limit(^params.limit)

    conf
    |> Repo.all(query)
    |> Enum.map(&to_workflow/1)
    |> sort(params)
  end

  defp params_with_defaults(params) do
    @defaults
    |> Map.merge(params)
    |> Map.update!(:sort_by, &maybe_atomize/1)
    |> Map.update!(:sort_dir, &maybe_atomize/1)
  end

  defp maybe_atomize(val) when is_binary(val), do: String.to_existing_atom(val)
  defp maybe_atomize(val), do: val

  # TODO: limit the amount of jobs to check in order to retrieve workflows
  defp base_query do
    Job
    |> where([j], fragment("? \\? 'workflow_id'", j.meta))
    |> group_by([j], fragment("?->>'workflow_id'", j.meta))
    |> select([j], %{
      workflow_id: fragment("?->>'workflow_id'", j.meta),
      workflow_name: fragment("min(?->>'workflow_name')", j.meta),
      total: count(),
      first_attempted_at: min(j.attempted_at),
      first_inserted_at: min(j.inserted_at),
      first_scheduled_at: min(j.scheduled_at),
      last_cancelled_at: max(j.cancelled_at),
      last_completed_at: max(j.completed_at),
      last_discarded_at: max(j.discarded_at),
      executing: fragment("count(*) FILTER (WHERE ? = 'executing')", j.state),
      available: fragment("count(*) FILTER (WHERE ? = 'available')", j.state),
      scheduled: fragment("count(*) FILTER (WHERE ? = 'scheduled')", j.state),
      retryable: fragment("count(*) FILTER (WHERE ? = 'retryable')", j.state),
      completed: fragment("count(*) FILTER (WHERE ? = 'completed')", j.state),
      cancelled: fragment("count(*) FILTER (WHERE ? = 'cancelled')", j.state),
      discarded: fragment("count(*) FILTER (WHERE ? = 'discarded')", j.state)
    })
  end

  defp order_query(query, %{sort_by: :time, sort_dir: :desc}),
    do: order_by(query, [j], desc: min(j.attempted_at))

  defp order_query(query, %{sort_by: :time, sort_dir: :asc}),
    do: order_by(query, [j], asc: min(j.attempted_at))

  defp order_query(query, _params),
    do: order_by(query, [j], desc: min(j.attempted_at))

  defp filter_ids(query, %{ids: ids}) when is_list(ids) and ids != [] do
    where(query, [j], fragment("?->>'workflow_id'", j.meta) in ^ids)
  end

  defp filter_ids(query, _params), do: query

  defp filter_names(query, %{names: names}) when is_list(names) and names != [] do
    where(query, [j], fragment("?->>'workflow_name'", j.meta) in ^names)
  end

  defp filter_names(query, _params), do: query

  defp to_workflow(row) do
    counts = %{
      executing: to_integer(row.executing),
      available: to_integer(row.available),
      scheduled: to_integer(row.scheduled),
      retryable: to_integer(row.retryable),
      completed: to_integer(row.completed),
      cancelled: to_integer(row.cancelled),
      discarded: to_integer(row.discarded)
    }

    %Workflow{
      id: to_string(row.workflow_id),
      name: row.workflow_name,
      state: Workflow.aggregate_state(counts),
      counts: counts,
      started_at: row.first_attempted_at,
      total_jobs: to_integer(row.total),
      inserted_at: row.first_inserted_at,
      scheduled_at: row.first_scheduled_at,
      attempted_at: row.first_attempted_at,
      cancelled_at: row.last_cancelled_at,
      completed_at: row.last_completed_at,
      discarded_at: row.last_discarded_at
    }
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(nil), do: 0

  # Graph Query

  def workflow_graph(conf, workflow_id) do
    conf.name
    |> Oban.Pro.Workflow.all_jobs(workflow_id, [])
    |> Enum.map(fn %Job{id: id, state: state, worker: worker, meta: meta} ->
      %{id: id, name: meta["name"], deps: meta["deps"] || [], state: state, worker: worker}
    end)
  end

  # Detail Queries

  def get_workflow(conf, workflow_id) do
    status = Oban.Pro.Workflow.status(conf.name, workflow_id)

    if status.state == :unknown do
      nil
    else
      %Workflow{
        id: status.id,
        name: status.name,
        state: status.state,
        counts: status.counts,
        total_jobs: status.total,
        started_at: status.started_at,
        inserted_at: status.started_at,
        scheduled_at: status.started_at,
        attempted_at: status.started_at,
        cancelled_at: status.stopped_at,
        completed_at: status.stopped_at,
        discarded_at: status.stopped_at
      }
    end
  end

  def workflow_jobs(params, conf, workflow_id) do
    params = params_with_defaults(params)

    query =
      workflow_id
      |> workflow_jobs_base()
      |> filter_job_states(params)
      |> filter_job_queues(params)
      |> filter_job_nodes(params)
      |> order_by([j], desc: j.id)
      |> limit(^params.limit)

    Repo.all(conf, query)
  end

  def workflow_job_filters(conf, workflow_id) do
    query =
      workflow_id
      |> workflow_jobs_base()
      |> workflow_job_filters_select()

    rows = Repo.all(conf, query)

    states =
      rows
      |> Enum.frequencies_by(& &1.state)
      |> Enum.sort_by(fn {state, _} -> state end)

    queues =
      rows
      |> Enum.frequencies_by(& &1.queue)
      |> Enum.sort_by(fn {queue, _} -> queue end)

    nodes =
      rows
      |> Enum.map(& &1.node)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {node, _} -> node end)

    %{states: states, queues: queues, nodes: nodes}
  end

  defp workflow_jobs_base(workflow_id) do
    Job
    |> where([j], fragment("?->>'workflow_id'", j.meta) == ^workflow_id)
  end

  defp workflow_job_filters_select(query) do
    select(query, [j], %{
      state: j.state,
      queue: j.queue,
      node: fragment("?[1]", j.attempted_by)
    })
  end

  defp filter_job_states(query, %{states: states}) when is_list(states) and states != [] do
    where(query, [j], j.state in ^states)
  end

  defp filter_job_states(query, _params), do: query

  defp filter_job_queues(query, %{queues: queues}) when is_list(queues) and queues != [] do
    where(query, [j], j.queue in ^queues)
  end

  defp filter_job_queues(query, _params), do: query

  defp filter_job_nodes(query, %{nodes: nodes}) when is_list(nodes) and nodes != [] do
    where(query, [j], fragment("?[1]", j.attempted_by) in ^nodes)
  end

  defp filter_job_nodes(query, _params), do: query

  # Sorting

  defp sort(workflows, %{sort_by: sort_by, sort_dir: sort_dir}) do
    Enum.sort_by(workflows, &order(&1, sort_by), sort_dir)
  end

  defp order(%{started_at: nil}, :time), do: 0

  defp order(%{started_at: started_at}, :time) do
    DateTime.to_unix(started_at, :millisecond)
  end

  defp order(%{name: nil}, :name), do: ""
  defp order(%{name: name}, :name), do: name

  defp order(%{total_jobs: total}, :total), do: total
end
