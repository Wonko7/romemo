defmodule Romemo do
  @moduledoc """
  Documentation for Romemo.


  from the XEP:
    IdentityKey
        Per-device public/private key pair used to authenticate communications
    PreKey
        A Diffie-Hellman public key, published in bulk and ahead of time
    PreKeySignalMessage
        An encrypted message that includes the initial key exchange. This is used to transparently build sessions with the first exchanged message.
    SignalMessage
        An encrypted message 
  """

  @timeout 5000
  @ns_omemo "eu.siacs.conversations.axolotl"
  @ns_omemo_devlist @ns_omemo <> ".devicelist"
  @ns_omemo_bundle @ns_omemo <> ".bundles:"

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
    state = %State{}
    %{jid: jid, pwd: pwd} = %State{}

    opts = [jid: jid, password: pwd]

    {:ok, conn} = Romeo.Connection.start_link(opts)
    {:ok, put_in(state, [:conn], conn)}
  end

  def handle_info(:connection_ready, %{conn: conn, jid: jid} = state) do
    conn
    |> get_roster()
    |> romeo_send(mk_pub_dev(jid))

    {:noreply, state}
  end

  def handle_info({:stanza, %{from: %{full: from_id}, xml: xml}}, %{jid: jid} = state) when from_id != jid do
    devices = xml
              |> safe_get_sub("pubsub")
              |> safe_get_sub("items")
              |> safe_get_sub("item")
              |> safe_get_sub("list")
              |> safe_get_subs("device")

    cond do
      devices -> 
        {:noreply, update_rooster_with_devices(devices, from_id, state)}

      true ->
        IO.puts("do not know what to do with this:")
        IO.inspect(xml)
        {:noreply, state}
    end
  end

  ## catch everything:
  def handle_info(a, state) do
    IO.puts("got_info:")
    IO.inspect(a)
    {:noreply, state}
  end

  def handle_info(a, _from, state) do
    IO.puts("got_info: with from")
    IO.inspect(a)
    {:noreply, state}
  end

  def handle_cast({:device_bundle, %IQ{xml: xml}, user, device}, state) do
    {:noreply, update_rooster_with_prekeys(xml, user, device, state)}
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

    roster
    |> Map.keys()
    |> Enum.each(&(romeo_send(conn, mk_get_dev(jid, &1))))

    {:noreply, %{state | roster: roster}}
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

  defp update_rooster_with_devices(devices_xml, user, state) do
    devices = Enum.map(devices_xml, &(Romeo.XML.attr(&1, "id")))

    IO.puts(">>>>>>>>> got devices for: " <> user)
    IO.inspect(devices)

    # Ask for a bundle for each of the user's devices:
    Enum.each(devices, &(update_dev_bundle(user, &1, state))) # FIXME: should not be here, temp

    #roster = %{roster | user => devices}
    IO.puts("new state:")
    IO.inspect(put_in(state, [:roster, user], Map.new(devices, &({&1, nil}))))

    put_in(state, [:roster, user], Map.new(devices, &({&1, nil})))
  end

  defp update_rooster_with_prekeys(prekeys_xml, user, device, state) do
    IO.puts(">>>>>>>>> got bundle: " <> user)
    IO.inspect(prekeys_xml)

    prekeys = prekeys_xml
              |> safe_get_sub("pubsub")
              |> safe_get_sub("items")
              |> safe_get_sub("item")
              |> safe_get_sub("bundle")
              |> safe_get_sub("prekeys")
              |> safe_get_subs("preKeyPublic")
              |> Enum.map(&extract_prekey/1)

    test_crypto(prekeys, user, device, state)

    put_in(state, [:roster, user, device], prekeys)
  end

  defp update_dev_bundle(user, device, %{conn: conn, jid: jid} = state) do
    msg = mk_get_bundle(jid, user, device)
    id = Romeo.XML.attr(msg, "id")
    romeo_send(conn, msg)

    receive do
      {:stanza, %IQ{id: ^id, type: "result"} = iq} ->
        GenServer.cast(self(), {:device_bundle, iq, user, device})
    after @timeout ->
      :ok
    end
  end

  ## get & handle roster from hedwig:
  defp get_roster(conn) do
    stanza = Romeo.Stanza.get_roster()
    id = Romeo.XML.attr(stanza, "id")
    Romeo.Connection.send(conn, stanza)

    receive do
      {:stanza, %IQ{id: ^id, type: "result"} = iq} ->
        GenServer.cast(self(), {:roster_results, iq})
    after @timeout ->
      :ok
    end

    conn
  end

  defp extract_prekey(prekey_xml), do: {Romeo.XML.attr(prekey_xml, "preKeyId"), Romeo.XML.cdata(prekey_xml)}

  defp safe_get_sub(nil, _), do: nil
  defp safe_get_sub(xml, e), do: Romeo.XML.subelement(xml, e)
  defp safe_get_subs(nil, _), do: nil
  defp safe_get_subs(xml, e), do: Romeo.XML.subelements(xml, e)

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

  ## <message to='juliet@capulet.lit' from='romeo@montague.lit' id='send1'>
  ##   <encrypted xmlns='eu.siacs.conversations.axolotl'>
  ##     <header sid='27183'>
  ##       <key rid='31415'>BASE64ENCODED...</key>
  ##       <key prekey="true" rid='12321'>BASE64ENCODED...</key>
  ##       <!-- ... -->
  ##       <iv>BASE64ENCODED...</iv>
  ##     </header>
  ##     <payload>BASE64ENCODED</payload>
  ##   </encrypted>
  ##   <store xmlns='urn:xmpp:hints'/>
  ## </message>

  # mk_msg("jid", "to", "prekey", "prekey_id", "key", "iv", "cipher_text")
  def mk_msg(jid, to, prekey_id, iv, key_and_cipher_tag, cipher_text) do
    xmlel(name: "message",
          attrs: [{"from", jid}, {"to", to}, {"type", "get"}, {"id", Romeo.Stanza.id()}],
          children: [xmlel(
            name: "encrypted",
            attrs: [{"xmlns", @ns_omemo}],
            children:
            [
              xmlel(
                name: "header",
                attrs: [{"sid", "42"}], # device sender ID
                children:
                [
                  xmlel(
                  name: "key",
                  attrs: [{"prekey", "true"}, {"rid", prekey_id}],
                  children: [xmlcdata(content: key_and_cipher_tag)]),
                  xmlel(
                  name: "iv",
                  children: [xmlcdata(content: iv)])
                ]),
              xmlel(
                name: "payload",
                attrs: [],
                children: [xmlcdata(content: cipher_text)])
            ])]
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

  defp romeo_send(conn, msg) do
    Romeo.Connection.send(conn, msg)
    conn
  end

  ### <test
  defp test_crypto(prekeys, user, device, %{conn: conn, jid: jid} = state) do
    {prekey_id, prekey_bytes} = hd(prekeys)
    prekey = Base.decode64(prekey_bytes, ignore: :whitespace)

    ## test crypto:
    {:ok, aes_128_key} = ExCrypto.generate_aes_key(:aes_128, :bytes)
    {:ok, iv} = ExCrypto.rand_bytes(16)
    {:ok, a_data} = ExCrypto.rand_bytes(128)
    clear_text = "brian is in the kitchen"

    {:ok, {ad, payload}} = ExCrypto.encrypt(aes_128_key, a_data, iv, clear_text)
    {c_iv, cipher_text, cipher_tag} = payload

    msg = mk_msg(jid, user, prekey_id, Base.encode64(c_iv), Base.encode64(aes_128_key <> cipher_tag), Base.encode64(cipher_text))
    #msg = mk_msg(jid, from_id, prekey_id, Base.encode64(c_iv), Base.encode64(aes_128_key <> a_data), Base.encode64(cipher_text))
    IO.puts(">>>>>>>>> made following message:")
    IO.inspect(msg)

    romeo_send(conn, Romeo.Stanza.normal(user, "oh hi mark"))
    romeo_send(conn, msg)

    IO.inspect(put_in(state, [:roster, user, device], prekeys))
  end
end
