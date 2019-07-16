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

use Mix.Config

config :astarte_rpc, :amqp_connection,
  host: System.get_env("RABBITMQ_HOST") || "rabbitmq"

config :astarte_pairing, :broker_url,
  "mqtts://broker.beta.astarte.cloud:8883/"

config :astarte_pairing, :cfssl_url,
  System.get_env("CFSSL_API_URL") || "http://ispirata-docker-alpine-cfssl-autotest:8080"

config :cqerl, :cassandra_nodes,
  [{System.get_env("CASSANDRA_DB_HOST") || "scylladb-scylla", System.get_env("CASSANDRA_DB_PORT") || 9042}]

config :bcrypt_elixir,
  log_rounds: 4
