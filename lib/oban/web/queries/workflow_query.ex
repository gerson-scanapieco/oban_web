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

  defguardp is_mysql(conf) when conf.engine == Oban.Engines.Dolphin

  defguardp is_sqlite(conf) when conf.engine == Oban.Engines.Lite

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
    query = dep_jobs_query(conf, workflow_id, dep_names)

    conf
    |> Repo.all(query)
    |> Map.new(fn %{name: name, id: id} -> {name, id} end)
  end

  defp dep_jobs_query(conf, workflow_id, dep_names) when is_mysql(conf) or is_sqlite(conf) do
    Job
    |> where([j], fragment("json_extract(?, '$.workflow_id')", j.meta) == ^workflow_id)
    |> where([j], fragment("json_extract(?, '$.name')", j.meta) in ^dep_names)
    |> select([j], %{name: fragment("json_extract(?, '$.name')", j.meta), id: j.id})
  end

  defp dep_jobs_query(_conf, workflow_id, dep_names) do
    Job
    |> where([j], fragment("?->>'workflow_id'", j.meta) == ^workflow_id)
    |> where([j], fragment("?->>'name'", j.meta) in ^dep_names)
    |> select([j], %{name: fragment("?->>'name'", j.meta), id: j.id})
  end

  def all_workflows(params, conf, _opts \\ []) do
    params = params_with_defaults(params)

    query = base_query(conf)

    query =
      query
      |> filter_ids(params, conf)
      |> filter_names(params, conf)
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

  defp base_query(conf) when is_mysql(conf) do
    Job
    |> where([j], fragment("json_extract(?, '$.workflow_id') IS NOT NULL", j.meta))
    |> group_by([j], fragment("json_extract(?, '$.workflow_id')", j.meta))
    |> select([j], %{
      workflow_id: fragment("json_extract(?, '$.workflow_id')", j.meta),
      workflow_name: fragment("min(json_extract(?, '$.workflow_name'))", j.meta),
      total: count(),
      first_attempted_at: min(j.attempted_at),
      executing: fragment("SUM(CASE WHEN ? = 'executing' THEN 1 ELSE 0 END)", j.state),
      available: fragment("SUM(CASE WHEN ? = 'available' THEN 1 ELSE 0 END)", j.state),
      scheduled: fragment("SUM(CASE WHEN ? = 'scheduled' THEN 1 ELSE 0 END)", j.state),
      retryable: fragment("SUM(CASE WHEN ? = 'retryable' THEN 1 ELSE 0 END)", j.state),
      completed: fragment("SUM(CASE WHEN ? = 'completed' THEN 1 ELSE 0 END)", j.state),
      cancelled: fragment("SUM(CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END)", j.state),
      discarded: fragment("SUM(CASE WHEN ? = 'discarded' THEN 1 ELSE 0 END)", j.state)
    })
  end

  defp base_query(conf) when is_sqlite(conf) do
    Job
    |> where([j], fragment("json_extract(?, '$.workflow_id') IS NOT NULL", j.meta))
    |> group_by([j], fragment("json_extract(?, '$.workflow_id')", j.meta))
    |> select([j], %{
      workflow_id: fragment("json_extract(?, '$.workflow_id')", j.meta),
      workflow_name: fragment("min(json_extract(?, '$.workflow_name'))", j.meta),
      total: count(),
      first_attempted_at: min(j.attempted_at),
      executing: fragment("SUM(CASE WHEN ? = 'executing' THEN 1 ELSE 0 END)", j.state),
      available: fragment("SUM(CASE WHEN ? = 'available' THEN 1 ELSE 0 END)", j.state),
      scheduled: fragment("SUM(CASE WHEN ? = 'scheduled' THEN 1 ELSE 0 END)", j.state),
      retryable: fragment("SUM(CASE WHEN ? = 'retryable' THEN 1 ELSE 0 END)", j.state),
      completed: fragment("SUM(CASE WHEN ? = 'completed' THEN 1 ELSE 0 END)", j.state),
      cancelled: fragment("SUM(CASE WHEN ? = 'cancelled' THEN 1 ELSE 0 END)", j.state),
      discarded: fragment("SUM(CASE WHEN ? = 'discarded' THEN 1 ELSE 0 END)", j.state)
    })
  end

  defp base_query(_conf) do
    Job
    |> where([j], fragment("? \\? 'workflow_id'", j.meta))
    |> group_by([j], fragment("?->>'workflow_id'", j.meta))
    |> select([j], %{
      workflow_id: fragment("?->>'workflow_id'", j.meta),
      workflow_name: fragment("min(?->>'workflow_name')", j.meta),
      total: count(),
      first_attempted_at: min(j.attempted_at),
      executing: fragment("count(*) FILTER (WHERE ? = 'executing')", j.state),
      available: fragment("count(*) FILTER (WHERE ? = 'available')", j.state),
      scheduled: fragment("count(*) FILTER (WHERE ? = 'scheduled')", j.state),
      retryable: fragment("count(*) FILTER (WHERE ? = 'retryable')", j.state),
      completed: fragment("count(*) FILTER (WHERE ? = 'completed')", j.state),
      cancelled: fragment("count(*) FILTER (WHERE ? = 'cancelled')", j.state),
      discarded: fragment("count(*) FILTER (WHERE ? = 'discarded')", j.state)
    })
  end

  defp filter_ids(query, %{ids: ids}, conf)
       when is_list(ids) and ids != [] do
    if is_mysql(conf) or is_sqlite(conf) do
      where(query, [j], fragment("json_extract(?, '$.workflow_id')", j.meta) in ^ids)
    else
      where(query, [j], fragment("?->>'workflow_id'", j.meta) in ^ids)
    end
  end

  defp filter_ids(query, _params, _conf), do: query

  defp filter_names(query, %{names: names}, conf)
       when is_list(names) and names != [] do
    if is_mysql(conf) or is_sqlite(conf) do
      where(query, [j], fragment("json_extract(?, '$.workflow_name')", j.meta) in ^names)
    else
      where(query, [j], fragment("?->>'workflow_name'", j.meta) in ^names)
    end
  end

  defp filter_names(query, _params, _conf), do: query

  defp to_workflow(row) do
    counts = %{
      "executing" => to_integer(row.executing),
      "available" => to_integer(row.available),
      "scheduled" => to_integer(row.scheduled),
      "retryable" => to_integer(row.retryable),
      "completed" => to_integer(row.completed),
      "cancelled" => to_integer(row.cancelled),
      "discarded" => to_integer(row.discarded)
    }

    %Workflow{
      id: to_string(row.workflow_id),
      name: row.workflow_name,
      state: Workflow.aggregate_state(counts),
      counts: counts,
      started_at: row.first_attempted_at,
      total_jobs: to_integer(row.total)
    }
  end

  defp to_integer(%Decimal{} = val), do: Decimal.to_integer(val)
  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(nil), do: 0

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
