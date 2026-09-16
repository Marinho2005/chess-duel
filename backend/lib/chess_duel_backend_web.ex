defmodule ChessDuelBackendWeb do
  @moduledoc """
  Interface de entrada para a camada web (controllers, channels, etc.).

  Este modulo centraliza os imports/aliases comuns aos componentes web roteados.
  """

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [json: ChessDuelBackendWeb.ErrorJSON],
        namespace: ChessDuelBackendWeb

      use Plug.ErrorHandler

      import Plug.Conn
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def json do
    quote do
      use Phoenix.Controller, formats: [:json], namespace: ChessDuelBackendWeb

      import Plug.Conn
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      @before_compile ChessDuelBackendWeb.ChannelAccess
    end
  end

  @doc """
  Quando usado, despacha para o macro apropriado (controller/json/channel).
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
