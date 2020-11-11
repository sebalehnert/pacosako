port module Api.LocalStorage exposing
    ( Data
    , LocalStorage
    , Permission(..)
    , load
    , setPermission
    , store
    )

{-| This module handles storing information in Local Storage as well as a
version history for it. Please keep in mind that we should always ask before
storing user information. This means each piece of data has a permission
attached to it that determines if it should be saved.

The format is:

    { version = Int
    , data = DataVx
    , permissions = [ Permission ]
    }

-}

import I18n.Strings exposing (Language(..), decodeLanguage, encodeLanguage)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import List.Extra as List


{-| Usable Local Storage object with all the migration details taken care of.
-}
type alias LocalStorage =
    { data : Data
    , permissions : List Permission
    }


decodeLocalStorage : Decoder LocalStorage
decodeLocalStorage =
    Decode.map2 LocalStorage
        decodeData
        (Decode.field "permissions" decodePermissionList)


{-| Stores the Data in the lastest version.
-}
encodeLocalStorage : LocalStorage -> Value
encodeLocalStorage ls =
    Encode.object
        [ ( "version", Encode.int latestVersion )
        , ( "data", encodeData ls.data )
        , ( "permissions", Encode.list encodePermission ls.permissions )
        ]


port writeToLocalStorage : Value -> Cmd msg


{-| Writes a LocalStorage object to the browsers local storage for later
retrival. Takes care of censorship.
-}
store : LocalStorage -> Cmd msg
store ls =
    { ls | data = censor ls.permissions ls.data }
        |> encodeLocalStorage
        |> writeToLocalStorage


{-| Tries to load data from local storage. If this fails for any reason a
default object is returned.
-}
load : Value -> LocalStorage
load value =
    Decode.decodeValue (Decode.field "localStorage" decodeLocalStorage) value
        |> Result.toMaybe
        |> Maybe.withDefault { data = defaultData, permissions = [] }


{-| A single permission that we got from the user. This module takes care of
only storing information that we have permissions for.

Data without permission:

  - Language: The language is not transfered to the server.

-}
type Permission
    = Username


setPermission : Permission -> Bool -> List Permission -> List Permission
setPermission entry shouldBeInList list =
    if shouldBeInList then
        if List.member entry list then
            list

        else
            entry :: list

    else
        List.remove entry list


encodePermission : Permission -> Value
encodePermission p =
    case p of
        Username ->
            Encode.string "Username"


decodePermission : Decoder Permission
decodePermission =
    Decode.string
        |> Decode.andThen
            (\str ->
                case str of
                    "Username" ->
                        Decode.succeed Username

                    otherwise ->
                        Decode.fail ("Not a permission: " ++ otherwise)
            )


{-| A defensive list decoder that will just discard entries that fail to decode
instead of failing the whole decode process.
-}
decodePermissionList : Decoder (List Permission)
decodePermissionList =
    Decode.list Decode.value
        |> Decode.map decodeDefensive


decodeDefensive : List Value -> List Permission
decodeDefensive values =
    List.filterMap
        (Decode.decodeValue decodePermission >> Result.toMaybe)
        values


{-| The latest data object for local storage. If the user is using an outdated
data model, it will be migrated automatically to the lastest version on load.
-}
type alias Data =
    DataV1


defaultData : Data
defaultData =
    { username = "", language = English }


latestVersion : Int
latestVersion =
    1


{-| While there are multiple decoders, there is only one encoder.
-}
encodeData : Data -> Value
encodeData data =
    Encode.object
        [ ( "username", Encode.string data.username )
        , ( "language", encodeLanguage data.language )
        ]


decodeData : Decoder Data
decodeData =
    Decode.field "version" Decode.int
        |> Decode.andThen (\version -> decodeDataVersioned version)


decodeDataVersioned : Int -> Decoder Data
decodeDataVersioned version =
    case version of
        1 ->
            Decode.field "data" decodeDataV1 |> Decode.map migrateDataV1

        _ ->
            Decode.fail "Version not supported, local storage corrupted."


{-| We don't want to store data where the user has not given us permission to
store it.
-}
censor : List Permission -> Data -> Data
censor permissions data =
    data
        |> censorUser permissions


type alias DataV1 =
    { username : String
    , language : Language
    }


migrateDataV1 : DataV1 -> Data
migrateDataV1 dataV1 =
    dataV1


censorUser : List Permission -> Data -> Data
censorUser permissions data =
    if List.member Username permissions then
        data

    else
        { data | username = "" }


decodeDataV1 : Decoder DataV1
decodeDataV1 =
    Decode.map2 DataV1
        (Decode.field "username" Decode.string)
        (Decode.field "language" decodeLanguage)



---- Various helper functions


encodeNullable : (a -> Value) -> Maybe a -> Value
encodeNullable encode thing =
    case thing of
        Just something ->
            encode something

        Nothing ->
            Encode.null
