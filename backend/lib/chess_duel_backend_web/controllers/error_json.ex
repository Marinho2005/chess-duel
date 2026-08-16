defmodule ChessDuelBackendWeb.ErrorJSON do
  @moduledoc """
  Renders JSON error for 404 and 500.
  """

  def render("404.json", _assigns) do
    %{errors: %{detail: "Not found"}}
  end

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal server error"}}
  end

  def template_not_found(_template, _assigns) do
    %{errors: %{detail: "Not found"}}
  end
end
