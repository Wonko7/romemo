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
              jid_mapping: %{},
              roster: []
  end



  def init(_) do
    %{jid: jid, pwd: pwd} = %State{}
    opts = [jid: jid, password: pwd]

    {:ok, conn} = Romeo.Connection.start_link(opts)
    {:ok, %State{conn: conn}}
  end

  def handle_info(:connection_ready, %{conn: conn, jid: jid} = state) do
    conn
    |> get_roster()
    |> romeo_send(mk_pub_dev(jid))

    {:noreply, state}
  end

  ## get & handle roster from hedwig:
  defp get_roster(conn) do
    stanza = Romeo.Stanza.get_roster()
    id = Romeo.XML.attr(stanza, "id")
    Romeo.Connection.send(conn, stanza)

    receive do
      {:stanza, %IQ{id: ^id, type: "result"} = iq} ->
        GenServer.cast(self, {:roster_results, iq})
    after @timeout ->
      :ok
    end

    conn
  end

  def handle_cast({:roster_results, %IQ{xml: xml}}, %{conn: conn, jid: jid} = state) do
    roster =
      xml
      |> Romeo.XML.subelement("query")
      |> Romeo.XML.subelements("item")
      |> Enum.map(&Romeo.XML.attr(&1, "jid"))
      |> Enum.reduce(%{}, &(Map.put(&2, &1, %{})))

    IO.puts("got roster")
    IO.inspect(roster)
    IO.inspect(Map.keys(roster))
    roster
    |> Map.keys()
    |> Enum.each(&(romeo_send(conn, mk_get_dev(jid, &1))))

    {:noreply, %{state | roster: roster}}
  end

  ## receive device list:
  ### {:stanza,
  ###   %Romeo.Stanza.IQ{
  ###     from: %Romeo.JID{full: "rule34@jabber.ccc.de", resource: "",
  ###       server: "jabber.ccc.de", user: "rule34"}, id: "a299", items: nil,
  ###     to: %Romeo.JID{full: "omemot1234@jabber.ccc.de/2748314061741500417347413",
  ###       resource: "2748314061741500417347413", server: "jabber.ccc.de",
  ###       user: "omemot1234"}, type: "result",
  ###     xml: {:xmlel, "iq",
  ###       [{"xml:lang", "en"},
  ###        {"to", "omemot1234@jabber.ccc.de/2748314061741500417347413"},
  ###        {"from", "rule34@jabber.ccc.de"}, {"type", "result"}, {"id", "a299"}],
  ###       [{:xmlel, "pubsub", [{"xmlns", "http://jabber.org/protocol/pubsub"}],
  ###         [{:xmlel, "items", [{"node", "eu.siacs.conversations.axolotl.devicelist"}],
  ###           [{:xmlel, "item", [{"id", "5E666BA8C5EF"}],
  ###             [{:xmlel, "list", [{"xmlns", "eu.siacs.conversations.axolotl"}],
  ###               [{:xmlel, "device", [{"id", "1961234194"}], []}]}]}]}]}]}}}


  def handle_info({:stanza, %{from: %{full: from_id}, xml: xml}}, %{roster: roster, jid: jid} = state) when from_id != jid do
    devices = xml
    |> Romeo.XML.subelement("pubsub")
    |> Romeo.XML.subelement("items")
    |> Romeo.XML.subelement("item")
    |> Romeo.XML.subelement("list")
    |> Romeo.XML.subelements("device")
    |> Enum.map(&(Romeo.XML.attr(&1, "id")))

    IO.puts(">>>>>>>>> got devices for: " <> from_id)
    IO.inspect(devices)
    roster = %{roster | from_id => devices}

    IO.puts("new roster:")
    IO.inspect(roster)
    {:noreply, %{state | roster: roster}}
  end

  ## there has to be a better way:
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
    IO.puts(">>>>>>>>>>>>>>>> Sending get devices to: " <> to)
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

  defp romeo_send(conn, msg) do
    Romeo.Connection.send(conn, msg)
    conn
  end

  ## catch everything:
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

end
