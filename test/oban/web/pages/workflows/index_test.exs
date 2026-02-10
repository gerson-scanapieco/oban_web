defmodule Oban.Web.Pages.Workflows.IndexTest do
  use Oban.Web.Case

  import Phoenix.LiveViewTest

  setup do
    start_supervised_oban!()

    {:ok, live, _html} = live(build_conn(), "/oban/workflows")

    {:ok, live: live}
  end

  test "viewing workflows with jobs", %{live: live} do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{},
      state: "executing",
      meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"}
    )

    insert_job!(%{},
      state: "executing",
      meta: %{workflow_id: wf_id, workflow_name: "my_pipeline"}
    )

    refresh(live)

    assert has_element?(live, "#workflows-table li#workflow-#{wf_id}")
  end

  test "showing empty state when no workflows", %{live: live} do
    refresh(live)

    assert has_element?(live, "#workflows-table", "No workflows")
  end

  test "sorting workflows by different properties", %{live: live} do
    wf_id = Ecto.UUID.generate()

    insert_job!(%{},
      state: "executing",
      meta: %{workflow_id: wf_id, workflow_name: "test"}
    )

    refresh(live)

    assert has_element?(live, "#workflows-sort")

    for mode <- ~w(name total) do
      change_sort(live, mode)

      assert_patch(
        live,
        workflows_path(limit: 20, sort_by: mode, sort_dir: "desc", states: "executing")
      )
    end
  end

  test "navigating to the workflows page", %{live: live} do
    assert has_element?(live, "#nav-workflows")
  end

  describe "pagination" do
    test "loading more workflows", %{live: live} do
      wf_id = Ecto.UUID.generate()

      insert_job!(%{},
        state: "executing",
        meta: %{workflow_id: wf_id, workflow_name: "test"}
      )

      refresh(live)

      live
      |> element("#workflows-table button", "Show More")
      |> render_click()

      assert_patch(live, workflows_path(limit: 40))
    end

    test "loading fewer workflows", %{live: _live} do
      {:ok, live, _html} = live(build_conn(), workflows_path(limit: 40))

      wf_id = Ecto.UUID.generate()

      insert_job!(%{},
        state: "executing",
        meta: %{workflow_id: wf_id, workflow_name: "test"}
      )

      refresh(live)

      live
      |> element("#workflows-table button", "Show Less")
      |> render_click()

      assert_patch(live, workflows_path(limit: 20))
    end
  end

  defp workflows_path(params) do
    "/oban/workflows?#{URI.encode_query(params)}"
  end

  defp refresh(live) do
    send(live.pid, :refresh)
  end

  defp change_sort(live, mode) do
    live
    |> element("a#sort-#{mode}")
    |> render_click()
  end
end
