defmodule PlanningPoker.SentryReqClientTest do
  use ExUnit.Case, async: true

  alias PlanningPoker.SentryReqClient

  defmodule EchoPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      {:ok, body, conn} = read_body(conn)

      conn
      |> put_resp_header("x-echo", "true")
      |> send_resp(200, "echo:" <> body)
    end
  end

  setup do
    {:ok, pid} = Bandit.start_link(plug: EchoPlug, port: 0)
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    %{port: port}
  end

  test "child_spec/0 describes the client" do
    assert %{id: SentryReqClient, start: {SentryReqClient, :start_link, []}} =
             SentryReqClient.child_spec()
  end

  test "start_link/0 returns the current process" do
    assert {:ok, pid} = SentryReqClient.start_link()
    assert pid == self()
  end

  test "post/3 returns status, headers and body", %{port: port} do
    assert {:ok, 200, headers, "echo:payload"} =
             SentryReqClient.post(
               "http://127.0.0.1:#{port}/api/1/store/",
               [{"content-type", "application/json"}],
               "payload"
             )

    assert headers["x-echo"] == ["true"]
  end

  test "post/3 returns an error when the server is unreachable" do
    assert {:error, _reason} = SentryReqClient.post("http://127.0.0.1:9/", [], "{}")
  end
end
