-module(er_logger_handler).

-define(MICROSECONDS_IN_SECONDS, 1000000).

% Logger callbacks
-export([log/2, filter_config/1, changing_config/3, adding_handler/1, removing_handler/1]).

%%%===================================================================
%%% Logger callbacks
%%%===================================================================

log(#{msg   := Message,
      level := Level,
      meta  := Meta} = _LogEvent,
    #{config := #{dsn                  := Dsn,
                  json_encode_function := JsonEncodeFunction,
                  event_tags_key       := EventTagsKey,
                  event_extra_key      := EventExtraKey,
                  fingerprint_key      := FingerprintKey
                 } = Config
     } = _HandlerConfig) ->
  EnvironmentContext = maps:get(environment_context, Config, undefined),

  RequestContext = maps:get(eraven_request_context, Meta, undefined),

  UserContext = maps:get(eraven_user_context, Meta, undefined),

  ProcessTags = maps:get(eraven_process_tags, Meta, #{}),
  EventTags = maps:get(EventTagsKey, Meta, #{}),
  Tags = maps:merge(ProcessTags, EventTags),

  ProcessExtra = maps:get(eraven_process_extra, Meta, #{}),
  EventExtra = maps:get(EventExtraKey, Meta, #{}),
  Extra = maps:merge(ProcessExtra, EventExtra),

  Fingerprint = maps:get(FingerprintKey, Meta, [<<"{{ default }}">>]),

  Context = er_context:new(EnvironmentContext, RequestContext, Extra, UserContext, Tags, #{}, Fingerprint),
  Event = build_event(format_message(Message), Level, Meta, Context),
  er_client:send_event(Event, Dsn, JsonEncodeFunction).

filter_config(Config) ->
  Config.

changing_config(update, OldConfig, NewConfig) ->
  OldParams = maps:get(config, OldConfig, #{}),
  NewParams = maps:get(config, NewConfig, #{}),
  {ok, NewConfig#{config => maps:merge(OldParams, NewParams)}}.

adding_handler(Config) ->
  {ok, Config}.

removing_handler(_Config) ->
  ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

format_message({string, Message}) ->
  Message;
format_message({Format, Data}) ->
  Formatted = io_lib:format(Format, Data),
  iolist_to_binary(Formatted).

-spec build_event(Message, Level, Metadata, Context) -> er_event:t() when
    Message  :: binary(),
    Level    :: logger:level(),
    Metadata :: map(),
    Context  :: er_context:t().
build_event(Message, Level, #{type := Type, reason := Reason, stacktrace := Stacktrace, time := Timestamp} = _Meta, Context) ->
  er_event:new(Message, Level, Type, Reason, Stacktrace, Context, Timestamp div ?MICROSECONDS_IN_SECONDS);
build_event(Message, Level, #{mfa := {Module, _Function, _Arity}, line := Line, time := Timestamp} = _Meta, Context) ->
  er_event:new(Message, Level, Module, Line, Context, Timestamp div ?MICROSECONDS_IN_SECONDS);
build_event(Message, Level, #{time := Timestamp} = _Meta, Context) ->
  er_event:new(Message, Level, Context, Timestamp div ?MICROSECONDS_IN_SECONDS).
