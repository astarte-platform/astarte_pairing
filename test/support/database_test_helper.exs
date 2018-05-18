#
# This file is part of Astarte.
#
# Astarte is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Astarte is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Astarte.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright (C) 2017-2018 Ispirata Srl
#

defmodule Astarte.Pairing.DatabaseTestHelper do
  alias Astarte.Core.Device
  alias Astarte.Pairing.Config
  alias Astarte.Pairing.TestHelper
  alias Astarte.Pairing.CredentialsSecret
  alias CQEx.Query
  alias CQEx.Client

  @create_autotestrealm """
  CREATE KEYSPACE autotestrealm
    WITH
    replication = {'class': 'SimpleStrategy', 'replication_factor': '1'} AND
    durable_writes = true;
  """

  @create_devices_table """
  CREATE TABLE autotestrealm.devices (
    device_id uuid,
    extended_id ascii,
    introspection map<ascii, int>,
    introspection_minor map<ascii, int>,
    protocol_revision int,
    triggers set<ascii>,
    metadata map<ascii, text>,
    inhibit_credentials_request boolean,
    credentials_secret ascii,
    cert_serial ascii,
    cert_aki ascii,
    first_credentials_request timestamp,
    last_connection timestamp,
    last_disconnection timestamp,
    connected boolean,
    pending_empty_cache boolean,
    total_received_msgs bigint,
    total_received_bytes bigint,
    last_credentials_request_ip inet,
    last_seen_ip inet,

    PRIMARY KEY (device_id)
  );
  """

  @drop_autotestrealm """
  DROP KEYSPACE autotestrealm;
  """

  @test_realm "autotestrealm"

  @unregistered_hw_id TestHelper.random_hw_id()

  @registered_not_confirmed_hw_id TestHelper.random_hw_id()
  @registered_not_confirmed_credentials_secret CredentialsSecret.generate()

  @registered_and_confirmed_hw_id TestHelper.random_hw_id()
  @registered_and_confirmed_credentials_secret CredentialsSecret.generate()

  @registered_and_inhibited_hw_id TestHelper.random_hw_id()
  @registered_and_inhibited_credentials_secret CredentialsSecret.generate()

  @insert_device """
  INSERT INTO devices
  (device_id, extended_id, credentials_secret, inhibit_credentials_request,
  protocol_revision, total_received_bytes, total_received_msgs, first_credentials_request)
  VALUES (:device_id, :extended_id, :credentials_secret, :inhibit_credentials_request,
  1, 0, 0, :first_credentials_request)
  """

  def test_realm(), do: @test_realm

  def unregistered_hw_id(), do: @unregistered_hw_id

  def registered_not_confirmed_hw_id(), do: @registered_not_confirmed_hw_id

  def registered_not_confirmed_credentials_secret(),
    do: @registered_not_confirmed_credentials_secret

  def registered_and_confirmed_hw_id(), do: @registered_and_confirmed_hw_id

  def registered_and_confirmed_credentials_secret(),
    do: @registered_and_confirmed_credentials_secret

  def registered_and_inhibited_hw_id(), do: @registered_and_inhibited_hw_id

  def registered_and_inhibited_credentials_secret(),
    do: @registered_and_inhibited_credentials_secret

  def create_db do
    client =
      Config.cassandra_node()
      |> Client.new!()

    with {:ok, _} <- Query.call(client, @create_autotestrealm),
         {:ok, _} <- Query.call(client, @create_devices_table) do
      :ok
    else
      %{msg: msg} -> {:error, msg}
    end
  end

  def seed_devices do
    client =
      Config.cassandra_node()
      |> Client.new!(keyspace: @test_realm)

    {:ok, registered_not_confirmed_device_id} =
      Device.decode_device_id(@registered_not_confirmed_hw_id, allow_extended_id: true)

    secret_hash = CredentialsSecret.hash(@registered_not_confirmed_credentials_secret)

    registered_not_confirmed_query =
      Query.new()
      |> Query.statement(@insert_device)
      |> Query.put(:device_id, registered_not_confirmed_device_id)
      |> Query.put(:extended_id, @registered_not_confirmed_hw_id)
      |> Query.put(:credentials_secret, secret_hash)
      |> Query.put(:inhibit_credentials_request, false)
      |> Query.put(:first_credentials_request, nil)

    {:ok, registered_and_confirmed_device_id} =
      Device.decode_device_id(@registered_and_confirmed_hw_id, allow_extended_id: true)

    secret_hash = CredentialsSecret.hash(@registered_and_confirmed_credentials_secret)

    registered_and_confirmed_query =
      Query.new()
      |> Query.statement(@insert_device)
      |> Query.put(:device_id, registered_and_confirmed_device_id)
      |> Query.put(:extended_id, @registered_and_confirmed_hw_id)
      |> Query.put(:credentials_secret, secret_hash)
      |> Query.put(:inhibit_credentials_request, false)
      |> Query.put(
        :first_credentials_request,
        DateTime.utc_now() |> DateTime.to_unix(:milliseconds)
      )

    {:ok, registered_and_inhibited_device_id} =
      Device.decode_device_id(@registered_and_inhibited_hw_id, allow_extended_id: true)

    secret_hash = CredentialsSecret.hash(@registered_and_inhibited_credentials_secret)

    registered_and_inhibited_query =
      Query.new()
      |> Query.statement(@insert_device)
      |> Query.put(:device_id, registered_and_inhibited_device_id)
      |> Query.put(:extended_id, @registered_and_inhibited_hw_id)
      |> Query.put(:credentials_secret, secret_hash)
      |> Query.put(:inhibit_credentials_request, true)
      |> Query.put(
        :first_credentials_request,
        DateTime.utc_now() |> DateTime.to_unix(:milliseconds)
      )

    with {:ok, _} <- Query.call(client, registered_not_confirmed_query),
         {:ok, _} <- Query.call(client, registered_and_confirmed_query),
         {:ok, _} <- Query.call(client, registered_and_inhibited_query) do
      :ok
    end
  end

  def clean_devices do
    client =
      Config.cassandra_node()
      |> Client.new!(keyspace: @test_realm)

    Query.call!(client, "TRUNCATE devices")

    :ok
  end

  def drop_db do
    client =
      Config.cassandra_node()
      |> Client.new!()

    Query.call(client, @drop_autotestrealm)
  end
end
