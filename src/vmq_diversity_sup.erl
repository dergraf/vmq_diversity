%% Copyright 2016 Erlio GmbH Basel Switzerland (http://erl.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%%%-------------------------------------------------------------------
%% @doc vmq_diversity top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module('vmq_diversity_sup').

-behaviour(supervisor).

%% API
-export([start_link/0,
         start_pool/2,
         start_all_pools/0,
         start_all_pools/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).
-define(CHILD(Id, Mod, Type, Args), {Id, {Mod, start_link, Args},
                                     permanent, 5000, Type, [Mod]}).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    {ok, { {one_for_all, 0, 1},
           [
            ?CHILD(vmq_diversity_plugin, vmq_diversity_plugin, worker, []),
            ?CHILD(vmq_diversity_script_sup, vmq_diversity_script_sup, supervisor, [])
           ]}
    }.

%%====================================================================
%% Internal functions
%%====================================================================

start_pool(Type, ProviderConfig) ->
    start_all_pools([{Type, ProviderConfig}], []).

start_all_pools() ->
    Providers = application:get_env(vmq_diversity, storage_providers, []),
    start_all_pools(Providers, []).

start_all_pools([{mysql, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    case emysql:add_pool(PoolId, PoolOpts) of
        ok ->
            start_all_pools(Rest, Acc);
        {error, pool_already_exists} ->
            % that's ok
            start_all_pools(Rest, Acc)
    end;
start_all_pools([{pgsql, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    Size = proplists:get_value(size, ProviderConfig, 10),
    MaxOverflow = proplists:get_value(max_overflow, ProviderConfig, 20),
    WorkerArgs = lists:keydelete(size, 1,
                                 lists:keydelete(max_overflow, 1, PoolOpts)),
    PoolArgs = [{name, {local, PoolId}},
                {worker_module, vmq_diversity_postgres},
                {size, Size},
                {max_overflow, MaxOverflow}],
    ChildSpec = poolboy:child_spec(PoolId, PoolArgs, WorkerArgs),
    start_all_pools(Rest, [ChildSpec|Acc]);
start_all_pools([{mongodb, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    Size = proplists:get_value(size, ProviderConfig, 10),
    MaxOverflow = proplists:get_value(max_overflow, ProviderConfig, 20),
    WorkerArgs = lists:keydelete(size, 1,
                                 lists:keydelete(max_overflow, 1, PoolOpts)),
    PoolArgs = [{name, {local, PoolId}},
                {worker_module, mc_worker},
                {size, Size},
                {max_overflow, MaxOverflow}],
    ChildSpec = poolboy:child_spec(PoolId, PoolArgs, WorkerArgs),
    start_all_pools(Rest, [ChildSpec|Acc]);
start_all_pools([{redis, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    Size = proplists:get_value(size, ProviderConfig, 10),
    MaxOverflow = proplists:get_value(max_overflow, ProviderConfig, 20),
    WorkerArgs = lists:keydelete(size, 1,
                                 lists:keydelete(max_overflow, 1, PoolOpts)),
    PoolArgs = [{name, {local, PoolId}},
                {worker_module, vmq_diversity_redis},
                {size, Size},
                {max_overflow, MaxOverflow}],
    ChildSpec = poolboy:child_spec(PoolId, PoolArgs, WorkerArgs),
    start_all_pools(Rest, [ChildSpec|Acc]);
start_all_pools([{memcached, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    Size = proplists:get_value(size, ProviderConfig, 10),
    MaxOverflow = proplists:get_value(max_overflow, ProviderConfig, 20),
    WorkerArgs = [proplists:get_value(host, PoolOpts),
                  proplists:get_value(port, PoolOpts)],
    PoolArgs = [{name, {local, PoolId}},
                {worker_module, vmq_diversity_memcached},
                {size, Size},
                {max_overflow, MaxOverflow}],
    ChildSpec = poolboy:child_spec(PoolId, PoolArgs, WorkerArgs),
    start_all_pools(Rest, [ChildSpec|Acc]);
start_all_pools([{kv, ProviderConfig}|Rest], Acc) ->
    TableId = proplists:get_value(id, ProviderConfig),
    TableOpts = proplists:get_value(opts, ProviderConfig, []),
    case lists:member(TableId, ets:all()) of
        false ->
            ets:new(TableId, [named_table, public,
                              {read_concurrency, true},
                              {write_concurrency, true}|TableOpts]);
        true ->
            ignore
    end,
    start_all_pools(Rest, Acc);
start_all_pools([{http, ProviderConfig}|Rest], Acc) ->
    PoolId = proplists:get_value(id, ProviderConfig),
    PoolOpts = proplists:get_value(opts, ProviderConfig, []),
    ok = hackney_pool:start_pool(PoolId, PoolOpts),
    start_all_pools(Rest, Acc);
start_all_pools([_|Rest], Acc) ->
    start_all_pools(Rest, Acc);
start_all_pools([], Acc) ->
    lists:foreach(fun(ChildSpec) ->
                          supervisor:start_child(?MODULE, ChildSpec)
                  end, Acc).
