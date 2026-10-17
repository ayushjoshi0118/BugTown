defmodule BugTownWeb.PageControllerTest do
  use BugTownWeb.ConnCase

  test "GET / renders BugTown command center", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "BUGTOWN"
    assert html_response(conn, 200) =~ "SYSTEM COMMAND CENTER"
  end
end
