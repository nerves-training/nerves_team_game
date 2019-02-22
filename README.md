# NervesTeamGame

NervesTeam Game Logic

This application provides the game logic for playing NervesTeam. It handles
messages from game clients and provides instructions for what those clients
should show next on their screens. All game interactions are through
function calls. Other modules glue this up to Phoenix Channels (or any
other transport). The API uses JSON strings to pass messages that are documented below.

NervesTeam clients are in two main states:

* Lobby - players connect here and wait for other players to join
* Game - after players start a game, control moves to the game state. New players can't join mid-game.

# Types

## Players

One NervesTeam client supports one player. Players are represented in JSON as

```json
{
  /* The player's name - one letter to fit on the display */
  "id": "a",

  /*
    * When the player is in the lobby, this indicates whether the player
    * wants to join a game. I.e., are they pressing the join button.
    */
  "ready": false,

  /*
    * In the game, this is the list of tasks for the player.
    * Each task is a string.
    */
  "tasks": []
}
```

See `NervesTeamGame.Player` for the Elixir representation.

## Tasks

During the game, `Tasks` of demands of a player that may be satisfied by that
player or another one.

```json
{
  /* Each task has a unique ID */
  "id": "nerves_time",

  /* The title is shown to the player */
  "title": "1970-01-01",

  /* Expire is the number of milliseconds that the player has for this task */
  "expire": 5000
}
```

## Actions

Players are presented `Actions` to complete their tasks.

```json
  {
  /* Each action has a unique ID */
  "id": "nerves_time",

  /* The title is shown to the player */
  "title": "nerves\ntime",
}
```

# Messages

Server messages will be delivered to the calling process in the form of

```elixir
{event :: String.t, payload :: map}
```

Clients can connect and interact with `NervesTeamGame` in many ways. One common
way is to use Phoenix Channels. Here is some basic setup for your channel
to handle messages the server will need.

```elixir
defmodule NervesTeamServerWeb.GameChannel do
  use NervesTeamServerWeb, :channel

  alias NervesTeamGame.{Lobby, Game}

  # Add the player to the lobby server
  def join("game:lobby", payload, socket) do
    if authorized?(payload) do
      {:ok, player} = Lobby.add_player()
      {:ok, assign(socket, :player, player)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  # Add the player to the game server
  def join("game:" <> game_id,
    %{"player_id" => player_id}, socket) do

    {:ok, player} = Game.player_join(game_id, player_id)
    {:ok, assign(socket, :player, player)}
  end

  # Update the lobby server player ready state
  def handle_in("player:ready", %{"ready" => ready?}, socket) do
    {:ok, _player} =
      Lobby.ready_player(socket.assigns.player.id, ready?)
    {:reply, :ok, socket}
  end

  # Executes the action on the game server
  def handle_in("action:execute", action,
    %{topic: "game:" <> game_id} = socket) do

    Game.action_execute(game_id, action)
    {:reply, :ok, socket}
  end

  # Pass messages from game server to the client
  def handle_info({event, payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
```

The following message examples will also show an example of what the client
message would look like when received over channels using [`phoenix_client`](https://github.com/mobileoverlord/phoenix_client)

## Lobby messages

Players always start in the lobby.

### Client -> Server

#### player:ready

Update the player ready state. Players need to set themselves to ready (true/false)
to be placed into a game. A game requires at least two ready players to begin.

Server example:

```elixir
NervesTeamGame.Lobby.ready_player("A", true)
```

PhoenixClient example:

```elixir
PhoenixClient.Channel.push("game:lobby", "player:ready", %{ready?: true})
```

### Server -> Client

**Player messages**
Player messages are only sent to individual players and not to everyone.

#### player:assigned

The player id was assigned to the connection.

Server message example:

```elixir
{"player:assigned", %NervesTeamGame.Player{id: "A"}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "player:assigned", payload: %{"id" => "A"}}
```

#### game:start

If more then one player are ready, the server will start a game after a specified
delay. After the delay, if more than one player is still ready, the server will
send the `game:start` message to _all_ players who are in the ready state.

Server message example:

```elixir
{"game:start", %{game_id: "1234", player_id: "A"}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:start", payload: %{"game_id" => "1234", "player_id" => "A"}}
```

**Broadcast messages**
Broadcast messages are are sent to everyone in the topic.

#### player:joined

When a player joins the lobby, all players will receive a message with the new
player information.

Server message example:

```elixir
{"player:joined", %NervesTeamGame.Player{id: "A"}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "player:joined", payload: %{"id" => "A"}}
```

#### player:left

When a player leaves the lobby, all players will receive a message with the
information for the player who left. The lobby server monitors the process id
that was sent when calling `NervesTeamGame.Lobby.add_player/1`. the `player:left`
message will be delivered if the monitored process dies.

Server message example:

```elixir
{"player:left", %NervesTeamGame.Player{id: "A"}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "player:left", payload: %{"id" => "A"}}
```

#### player:list

The player list message is delivered any time a player is added or removed from
the lobby. This is useful if you do not wish to track a copy of the player list
through `player:joined` / `player:left` messages.

Server message example:

```elixir
{"player:list", %{players: [%NervesTeamGame.Player{id: "A"}]}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "player:list", payload: %{"players" => [%{"id" => "A"}]}}
```

#### game:pending

When more than one player is ready, the server will send the `game:pending` message
to inform all players that a new game will begin shortly.

Server message example:

```elixir
{"game:pending", %{duration: 2000}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:pending", payload: %{"duration" => 2000}}
```

#### game:wait

If the server delivers a `game:pending` message and enough players become not
ready where the number of ready players < 1, the server will cancel the pending
game and send the `game:wait` message.

Server message example:

```elixir
{"game:wait", %{}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:wait", payload: %{}}
```

## Game messages

### Client -> Server

#### action:execute

Actions are associated to tasks. In order to win the game, tasks must have their
actions executed before the task expires. The server needs to know when an action
has been executed so it can update the game score.

Server example:

```elixir
NervesTeamGame.Game.action_execute("1234", "nerves_time")
```

PhoenixClient example:

```elixir
PhoenixClient.Channel.push("game:1234", "action:execute", %{id: "nerves_time"})
```

### Server -> Client

**Player messages**
Player messages are only sent to individual players and not to everyone.

#### actions:assigned

Before the game starts, the server will assign two actions to each player.
Each action will contain an id which will be sent to the server when executing
the action.

Server message example:

```elixir
{"actions:assigned", %{actions: [%NervesTeamGame.Game.Task.Action{id: :nerves_time, title: "nerves\ntime"}, %NervesTeamGame.Game.Task.Action{id: :git_rebase, title: "merge\nconflict"}]}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "actions:assigned", payload: %{"actions" => [%{"id" => "nerves_time", "title" => "nerves\ntime"}, %{"id" => "git_rebase", "title" => "merge\nconflict"}]}}
```

#### task:assigned

New tasks will be assigned to the player when either their current task has expired
or their current task's action has been executed by a player.

```elixir
{"task:assigned", %NervesTeamGame.Game.Task{id: :nerves_time, title: "1970-01-01"}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "task:assigned", payload: %{"id" => "nerves_time", "title" => "1970-01-01"}}
```

**Broadcast messages**
Broadcast messages are are sent to everyone in the topic.

#### game:prepare

Once all required players have joined the game, the server will send the `game:prepare`
message and begin to distribute tasks and actions. It will wait for the specified
duration before moving to `game:starting`

Server message example:

```elixir
{"game:prepare", %{duration: 1000}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:prepare", payload: %{"duration" => 1000}}
```

#### game:prepare

After the `game:prepare` duration is exceeded, the server will send the message
`game:starting`. This is useful for updating the player's display to inform them
that all work is done and the game is about to start.

Server message example:

```elixir
{"game:starting", %{duration: 2000}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:starting", payload: %{"duration" => 2000}}
```

#### game:start

After the `game:starting` duration is exceeded, the server will send the message
`game:start` to mark the start of the game.

Server message example:

```elixir
{"game:start", %{}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:start", payload: %{}}
```

#### game:progress

Game progress is sent at an interval and will represent the percent complete.
The goal is to get to 100% to win the game. Games are limited to 3 minutes. On every
tick of the interval, some progress is removed to increase difficulty.

Server message example:

```elixir
{"game:progress", %{percent: 100}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:progress", payload: %{"percent" => 100}}
```

#### game:ended

The server will send the `game:ended` message when game progress == 100 or 0.
When the games ends, the server will inform the players if they have won or lost.

Server message example:

```elixir
{"game:ended", %{win?: true}}
```

PhoenixClient message example:

```elixir
%PhoenixClient.Message{event: "game:ended", payload: %{"win?" => true}}
```
