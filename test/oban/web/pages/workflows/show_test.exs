defmodule Oban.Web.Pages.Workflows.ShowTest do
  use Oban.Web.Case

  import Phoenix.LiveViewTest

  setup do
    start_supervised_oban!()

    :ok
  end

  test "viewing workflow details with jobs" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"}, worker: WorkerA)
    insert_job!(%{}, meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"}, worker: WorkerB)

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#workflow-details")
    assert has_element?(live, "#workflow-details", "my_pipeline")
    assert has_element?(live, "#workflow-details", "Workflow Details")
  end

  test "showing workflow jobs in the detail view" do
    wf_id = Ecto.UUID.generate()

    job_a = insert_job!(%{}, meta: %{workflow_id: wf_id}, worker: WorkerA)
    job_b = insert_job!(%{}, meta: %{workflow_id: wf_id}, worker: WorkerB)

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#wf-job-#{job_a.id}")
    assert has_element?(live, "#wf-job-#{job_b.id}")
  end

  test "redirecting to list for non-existent workflow" do
    assert {:error, {:live_redirect, %{to: "/oban/workflows"}}} =
             live(build_conn(), "/oban/workflows/#{Ecto.UUID.generate()}")
  end

  test "navigating back from detail to list" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id, workflow_name: "test"})

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#back-link")
  end

  test "sidebar displays states for workflow jobs" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id})

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#states")
  end

  test "sidebar displays queues for workflow jobs" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id}, queue: :alpha)

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#queues")
  end

  test "filtering jobs by state via sidebar" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id})

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    live
    |> element("#filter-available")
    |> render_click()

    assert_patch(live, "/oban/workflows/#{wf_id}?states=available")
  end

  test "rendering the workflow timeline" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id})

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#wf-timeline-for-inserted")
    assert has_element?(live, "#wf-timeline-for-scheduled")
    assert has_element?(live, "#wf-timeline-for-executing")
    assert has_element?(live, "#wf-timeline-for-cancelled")
    assert has_element?(live, "#wf-timeline-for-discarded")
  end

  test "refreshing the detail view" do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{}, meta: %{workflow_id: wf_id, workflow_name: "pipeline"})

    {:ok, live, _html} = live(build_conn(), "/oban/workflows/#{wf_id}")

    assert has_element?(live, "#workflow-details")

    send(live.pid, :refresh)

    assert has_element?(live, "#workflow-details")
  end
end
