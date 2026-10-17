defmodule BugTownWeb.PageController do
  use BugTownWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
