defmodule NervesTeamGame do
  @moduledoc """
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
    /* Each task has a unique ID
    "id": "nerves_time",

    /* The title is shown to the player
    "title": "1970-01-01",

    /* Expire is the number of milliseconds that the player has for this task */
    "expire": 5000
  }
  ```

  ## Actions

  Players are presented `Actions` to complete their tasks.

  ```json
    {
    /* Each action has a unique ID
    "id": "nerves_time",

    /* The title is shown to the player
    "title": "1970-01-01",
  }
  ```

  # Messages

  ## Lobby messages

  Players always start in the lobby.

  ### Client -> Server

  ### Server -> Client

  Player messages

  ```json
    {"player:assigned", %NervesTeamGame.Player{}}
    {"game:start", %{game_id: "", player_id: ""}}
  ```

  Global messages

  ```json
    {"player:joined", %NervesTeamGame.Player{}}
    {"player:left", %NervesTeamGame.Player{}}
    {"player:list", [%NervesTeamGame.Player{}, ...]}
    {"game:pending", %{duration: 1000}}
    {"game:wait", %{}}
  ```

  ## Game messages

  ### Client -> Server

  ### Server -> Client

  Player messages

  ```
    {"actions:assigned", [%NervesTeamGame.Game.Task.Action{}, ...]}
    {"task:assigned", %NervesTeamGame.Game.Task{}}
  ```

  Global messages

  ```
    {"game:prepare", %{duration: 2000}}
    {"game:starting", %{duration: 1000}}
    {"game:start", %{}}
    {"game:progress", %{percent: 0..100}}
    {"game:ended", %{win?: true/false}}
  ```
  """
end
