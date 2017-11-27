defmodule Romemo do
  @moduledoc """
  Documentation for Romemo.
  """

  @timeout 5000
  @ns_omemo "eu.siacs.conversations.axolotl"
  @ns_omemo_devlist @ns_omemo <> ".devicelist"
  @ns_omemo_bundle @ns_omemo <> ".bundles:"

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

  defp safe_get_sub(nil, _), do: nil
  defp safe_get_sub(xml, e), do: Romeo.XML.subelement(xml, e)
  defp safe_get_subs(nil, _), do: nil
  defp safe_get_subs(xml, e), do: Romeo.XML.subelements(xml, e)

  def handle_info({:stanza, %{from: %{full: from_id}, xml: xml}}, %{conn: conn, roster: roster, jid: jid} = state) when from_id != jid do
    devices = xml
              |> safe_get_sub("pubsub")
              |> safe_get_sub("items")
              |> safe_get_sub("item")
              |> safe_get_sub("list")
              |> safe_get_subs("device")
              #|> Enum.map(&(Romeo.XML.attr(&1, "id")))

    bundle = xml
             |> safe_get_sub("pubsub")
             |> safe_get_sub("items")
             |> safe_get_sub("item")
             |> safe_get_sub("bundle")
    if devices do
      devices = Enum.map(devices, &(Romeo.XML.attr(&1, "id")))

      IO.puts(">>>>>>>>> got devices for: " <> from_id)
      IO.inspect(devices)

      Enum.each(devices, &(romeo_send(conn, mk_get_bundle(jid, from_id, &1))))

      roster = %{roster | from_id => devices}

      IO.puts("new roster:")
      IO.inspect(roster)
      {:noreply, %{state | roster: roster}}
    else
      IO.puts(">>>>>>>>> got something else for: " <> from_id)
      IO.inspect(bundle)
      {:noreply, state}
    end
  end

  ## catch everything:
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

  defp romeo_send(conn, msg) do
    Romeo.Connection.send(conn, msg)
    conn
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
                    attrs: [{"id", "42"}] # FIXME: id hardcoded for now
                  )]
                )]
              )]
            )]
          )]
    )
  end

  defp mk_get_dev(jid, to) do
    IO.puts(">>>>>>>>>>>>>>>> get devices to: " <> to)
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

  ## <iq type='get'
  ##   from='romeo@montague.lit'
  ##   to='juliet@capulet.lit'
  ##   id='fetch1'>
  ##   <pubsub xmlns='http://jabber.org/protocol/pubsub'>
  ##     <items node='eu.siacs.conversations.axolotl.bundles:31415'/>
  ##   </pubsub>
  ## </iq>
  defp mk_get_bundle(jid, to, device) do
    IO.puts(">>>>>>>>>>>>>>>> get bundle to: " <> to <> ":" <> device)
    xmlel(name: "iq",
          attrs: [{"from", jid}, {"to", to}, {"type", "get"}, {"id", Romeo.Stanza.id()}],
          children: [xmlel(
            name: "pubsub",
            attrs: [{"xmlns", ns_pubsub()}],
            children: [xmlel(
              name: "items",
              attrs: [{"node", @ns_omemo_bundle <> device}]
            )]
          )])
  end
end
