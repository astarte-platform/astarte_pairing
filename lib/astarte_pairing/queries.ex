#
# This file is part of Astarte.
#
# Copyright 2017-2018 Ispirata Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

defmodule Astarte.Pairing.Queries do
  @moduledoc """
  This module is responsible for the interaction with the database.
  """

  alias CQEx.Query
  alias CQEx.Result

  require Logger

  @protocol_revision 1

  def get_agent_public_key_pems(client) do
    get_jwt_public_key_pem = """
    SELECT blobAsVarchar(value)
    FROM kv_store
    WHERE group='auth' AND key='jwt_public_key_pem';
    """

    # TODO: add additional keys
    query =
      Query.new()
      |> Query.statement(get_jwt_public_key_pem)

    with {:ok, res} <- Query.call(client, query),
         ["system.blobasvarchar(value)": pem] <- Result.head(res) do
      {:ok, [pem]}
    else
      :empty_dataset ->
        {:error, :public_key_not_found}

      error ->
        Logger.warn("DB error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  def register_device(client, device_id, extended_id, credentials_secret, opts \\ []) do
    statement = """
    SELECT first_credentials_request, first_registration
    FROM devices
    WHERE device_id=:device_id
    """

    device_exists_query =
      Query.new()
      |> Query.statement(statement)
      |> Query.put(:device_id, device_id)
      |> Query.consistency(:quorum)

    with {:ok, res} <- Query.call(client, device_exists_query) do
      case Result.head(res) do
        :empty_dataset ->
          registration_timestamp =
            DateTime.utc_now()
            |> DateTime.to_unix(:milliseconds)

          Logger.info("register request for new device: #{inspect(extended_id)}")
          do_register_device(client, device_id, credentials_secret, registration_timestamp, opts)

        [first_credentials_request: nil, first_registration: registration_timestamp] ->
          Logger.info("register request for existing unconfirmed device: #{inspect(extended_id)}")
          do_register_device(client, device_id, credentials_secret, registration_timestamp, opts)

        [first_credentials_request: _timestamp, first_registration: _registration_timestamp] ->
          Logger.warn("register request for existing confirmed device: #{inspect(extended_id)}")
          {:error, :already_registered}
      end
    else
      error ->
        Logger.warn("DB error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  def select_device_for_credentials_request(client, device_id) do
    statement = """
    SELECT first_credentials_request, cert_aki, cert_serial, inhibit_credentials_request, credentials_secret
    FROM devices
    WHERE device_id=:device_id
    """

    do_select_device(client, device_id, statement)
  end

  def select_device_for_info(client, device_id) do
    statement = """
    SELECT credentials_secret, inhibit_credentials_request, first_credentials_request
    FROM devices
    WHERE device_id=:device_id
    """

    do_select_device(client, device_id, statement)
  end

  def select_device_for_verify_credentials(client, device_id) do
    statement = """
    SELECT credentials_secret
    FROM devices
    WHERE device_id=:device_id
    """

    do_select_device(client, device_id, statement)
  end

  def update_device_after_credentials_request(client, device_id, cert_data, device_ip, nil) do
    first_credentials_request_timestamp =
      DateTime.utc_now()
      |> DateTime.to_unix(:milliseconds)

    update_device_after_credentials_request(
      client,
      device_id,
      cert_data,
      device_ip,
      first_credentials_request_timestamp
    )
  end

  def update_device_after_credentials_request(
        client,
        device_id,
        %{serial: serial, aki: aki} = _cert_data,
        device_ip,
        first_credentials_request_timestamp
      ) do
    statement = """
    UPDATE devices
    SET cert_aki=:cert_aki, cert_serial=:cert_serial, last_credentials_request_ip=:last_credentials_request_ip,
    first_credentials_request=:first_credentials_request
    WHERE device_id=:device_id
    """

    query =
      Query.new()
      |> Query.statement(statement)
      |> Query.put(:device_id, device_id)
      |> Query.put(:cert_aki, aki)
      |> Query.put(:cert_serial, serial)
      |> Query.put(:last_credentials_request_ip, device_ip)
      |> Query.put(:first_credentials_request, first_credentials_request_timestamp)
      |> Query.put(:protocol_revision, @protocol_revision)
      |> Query.consistency(:quorum)

    case Query.call(client, query) do
      {:ok, _res} ->
        :ok

      error ->
        Logger.warn("DB error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  defp do_select_device(client, device_id, select_statement) do
    device_query =
      Query.new()
      |> Query.statement(select_statement)
      |> Query.put(:device_id, device_id)
      |> Query.consistency(:quorum)

    with {:ok, res} <- Query.call(client, device_query),
         device_row when is_list(device_row) <- Result.head(res) do
      {:ok, device_row}
    else
      :empty_dataset ->
        {:error, :device_not_found}

      error ->
        Logger.warn("DB error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  defp do_register_device(client, device_id, credentials_secret, registration_timestamp, opts) do
    statement = """
    INSERT INTO devices
    (device_id, first_registration, credentials_secret, inhibit_credentials_request,
    protocol_revision, total_received_bytes, total_received_msgs, introspection,
    introspection_minor)
    VALUES
    (:device_id, :first_registration, :credentials_secret, :inhibit_credentials_request,
    :protocol_revision, :total_received_bytes, :total_received_msgs, :introspection,
    :introspection_minor)
    """

    {introspection, introspection_minor} =
      opts
      |> Keyword.get(:initial_introspection, [])
      |> build_initial_introspection_maps()

    query =
      Query.new()
      |> Query.statement(statement)
      |> Query.put(:device_id, device_id)
      |> Query.put(:first_registration, registration_timestamp)
      |> Query.put(:credentials_secret, credentials_secret)
      |> Query.put(:inhibit_credentials_request, false)
      |> Query.put(:protocol_revision, 0)
      |> Query.put(:total_received_bytes, 0)
      |> Query.put(:total_received_msgs, 0)
      |> Query.put(:introspection, introspection)
      |> Query.put(:introspection_minor, introspection_minor)
      |> Query.consistency(:quorum)

    case Query.call(client, query) do
      {:ok, _res} ->
        :ok

      error ->
        Logger.warn("DB error: #{inspect(error)}")
        {:error, :database_error}
    end
  end

  defp build_initial_introspection_maps(initial_introspection) do
    Enum.reduce(initial_introspection, {[], []}, fn introspection_entry, {majors, minors} ->
      %{
        interface_name: interface_name,
        major_version: major_version,
        minor_version: minor_version
      } = introspection_entry

      {[{interface_name, major_version} | majors], [{interface_name, minor_version} | minors]}
    end)
  end
end
