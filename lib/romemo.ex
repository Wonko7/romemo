defmodule Romemo do
  @moduledoc """
  Documentation for Romemo.
  """

  @timeout 5000
  @ns_omemo "eu.siacs.conversations.axolotl"
  @ns_omemo_devlist @ns_omemo <> ".devicelist"

  @jid_to "rule34@jabber.ccc.de"

  use Romeo.XML
  use GenServer
  require Logger

  defmodule State do
    defstruct conn: nil,
              jid: "omemot1234@jabber.ccc.de",
              pwd: "lolilol",
              jid_mapping: %{}
  end



  def init(_) do
    %{jid: jid, pwd: pwd} = %State{}
    opts = [jid: jid, password: pwd]

    {:ok, conn} = Romeo.Connection.start_link(opts)
    {:ok, %State{conn: conn}}
  end

  def handle_info(:connection_ready, %{conn: conn, jid: jid} = state) do
    Romeo.Connection.send(conn, mk_pub_dev(jid))
    Romeo.Connection.send(conn, mk_get_dev(jid, @jid_to))

    {:noreply, state}
  end

  def handle_cast(a, state) do
    IO.puts("got_cast:")
    IO.inspect(a)
    {:noreply, state}
  end

  def handle_cast(a, _from, state) do
    IO.puts("got_cast: with from")
    IO.inspect(a)
    {:noreply, state}
  end

  def handle_info(a, _from, state) do
    IO.puts("got_info: with from")
    IO.inspect(a)
    {:noreply, state}
  end

  def handle_info(a, state) do
    IO.puts("got_info:")
    IO.inspect(a)
    {:noreply, state}
  end

  def hello do
    :world
  end

  defp mk_pub_dev(jid) do
    xmlel(name: "iq",
          attrs: [{"from", jid}, {"type", "set"}, {"id", Romeo.Stanza.id()}],
          children: [xmlel(
            name: "pubsub",
            attrs: [{"xmlns", ns_pubsub()}],
            children: [xmlel(
              name: "publish",
              attrs: [{"node", @ns_omemo_devlist}],
              children: [xmlel(
                name: "item",
                children: [xmlel(
                  attrs: [{"xmlns", @ns_omemo}],
                  name: "list",
                  children: [xmlel(
                    name: "device",
                    attrs: [{"id", "42"}]
                  )]
                )]
              )]
            )]
          )]
    )
  end

  defp  mk_get_dev(jid, to) do
    xmlel(name: "iq",
          attrs: [{"from", jid}, {"to", to}, {"type", "get"}, {"id", Romeo.Stanza.id()}],
          children: [xmlel(
            name: "pubsub",
            attrs: [{"xmlns", ns_pubsub()}],
            children: [xmlel(
              name: "items",
              attrs: [{"node", @ns_omemo_devlist}]
            )]
          )])
  end


end
