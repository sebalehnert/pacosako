module CastingDeco exposing
    ( InputMode(..)
    , Messages
    , Model
    , clearArrows
    , clearTiles
    , configView
    , initModel
    , mouseDown
    , mouseMove
    , mouseUp
    , toDecoration
    )

import Arrow exposing (Arrow)
import Components exposing (btn, isEnabledIf, isSelectedIf, viewButton, withMsg, withMsgIf)
import Custom.Events exposing (BoardMousePosition)
import Element exposing (Element, padding, spacing)
import Element.Background as Background
import Element.Font as Font
import Element.Input as Input
import I18n.Strings exposing (I18nToken(..), Language, t)
import List.Extra as List
import Sako exposing (Tile)


type alias Model =
    { tiles : List Tile
    , arrows : List Arrow
    , ghostArrow : Maybe Arrow
    }


initModel : Model
initModel =
    { tiles = []
    , arrows = []
    , ghostArrow = Nothing
    }


type InputMode
    = InputTiles
    | InputArrows


mouseDown : InputMode -> BoardMousePosition -> Model -> Model
mouseDown mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows ->
            mouseDownArrows mouse model


{-| Create a ghost arrow.
-}
mouseDownArrows : BoardMousePosition -> Model -> Model
mouseDownArrows mouse model =
    { model | ghostArrow = Maybe.map2 Arrow mouse.tile mouse.tile }


mouseMove : InputMode -> BoardMousePosition -> Model -> Model
mouseMove mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            model

        InputArrows ->
            mouseMoveArrows mouse model


{-| Update the ghost arrow if it exists.
-}
mouseMoveArrows : BoardMousePosition -> Model -> Model
mouseMoveArrows mouse model =
    { model
        | ghostArrow =
            Maybe.map2 setHead mouse.tile model.ghostArrow
    }


setHead : Tile -> Arrow -> Arrow
setHead head arrow =
    { arrow | head = head }


mouseUp : InputMode -> BoardMousePosition -> Model -> Model
mouseUp mode mouse model =
    case mode of
        InputTiles ->
            -- Nothing to do here, tile is shown on mouse up.
            mouseUpTiles mouse model

        InputArrows ->
            model
                |> mouseMoveArrows mouse
                |> mouseUpArrows


{-| Commit the ghost arrow to the arrows map or remove it if it already exists.
-}
mouseUpArrows : Model -> Model
mouseUpArrows model =
    case model.ghostArrow of
        Just ghostArrow ->
            { model
                | ghostArrow = Nothing
                , arrows = ghostArrow :: model.arrows
            }

        Nothing ->
            model


mouseUpTiles : BoardMousePosition -> Model -> Model
mouseUpTiles mouse model =
    case mouse.tile of
        Just tile ->
            { model | tiles = flipEntry tile model.tiles }

        Nothing ->
            model


flipEntry : a -> List a -> List a
flipEntry entry list =
    if List.member entry list then
        List.remove entry list

    else
        entry :: list


{-| Removes all tiles.
-}
clearTiles : Model -> Model
clearTiles model =
    { model | tiles = [] }


{-| Removes all tiles.
-}
clearArrows : Model -> Model
clearArrows model =
    { model | arrows = [], ghostArrow = Nothing }


{-| Helper function to display the tiles and arrows.
-}
toDecoration : { tile : Tile -> a, arrow : Arrow -> a } -> Model -> List a
toDecoration mappers model =
    List.map mappers.tile model.tiles
        ++ List.map mappers.arrow (allArrows model)


allArrows : Model -> List Arrow
allArrows model =
    case model.ghostArrow of
        Just arrow ->
            arrow :: model.arrows

        Nothing ->
            model.arrows


type alias Messages msg =
    { setInputMode : Maybe InputMode -> msg
    , clearTiles : msg
    , clearArrows : msg
    }


{-| Input element where you can manage the casting deco.
-}
configView : Language -> Messages msg -> Maybe InputMode -> Model -> Element msg
configView lang messages mode model =
    Element.column [ spacing 5 ]
        [ normalInputModeButton lang messages mode
        , tileInputMode lang messages mode model
        , arrowInputMode lang messages mode model
        ]


normalInputModeButton : Language -> Messages msg -> Maybe InputMode -> Element msg
normalInputModeButton lang messages mode =
    btn (t lang i18nNormalMode)
        |> withMsg (messages.setInputMode Nothing)
        |> isSelectedIf (mode == Nothing)
        |> viewButton


tileInputMode : Language -> Messages msg -> Maybe InputMode -> Model -> Element msg
tileInputMode lang messages mode model =
    Element.row [ spacing 5 ]
        [ tileInputModeButton lang messages mode
        , tileInputClearButton lang messages model
        ]


tileInputModeButton : Language -> Messages msg -> Maybe InputMode -> Element msg
tileInputModeButton lang messages mode =
    btn (t lang i18nHighlight)
        |> withMsg (messages.setInputMode (Just InputTiles))
        |> withMsgIf (mode == Just InputTiles) (messages.setInputMode Nothing)
        |> isSelectedIf (mode == Just InputTiles)
        |> viewButton


tileInputClearButton : Language -> Messages msg -> Model -> Element msg
tileInputClearButton lang messages model =
    btn (t lang i18nClearHighlight)
        |> withMsgIf (not <| List.isEmpty model.tiles) messages.clearTiles
        |> isEnabledIf (not <| List.isEmpty model.tiles)
        |> viewButton


arrowInputMode : Language -> Messages msg -> Maybe InputMode -> Model -> Element msg
arrowInputMode lang messages mode model =
    Element.row [ spacing 5 ]
        [ arrowInputModeButton lang messages mode
        , arrowInputClearButton lang messages model
        ]


arrowInputModeButton : Language -> Messages msg -> Maybe InputMode -> Element msg
arrowInputModeButton lang messages mode =
    btn (t lang i18nArrows)
        |> withMsg (messages.setInputMode (Just InputArrows))
        |> withMsgIf (mode == Just InputArrows) (messages.setInputMode Nothing)
        |> isSelectedIf (mode == Just InputArrows)
        |> viewButton


arrowInputClearButton : Language -> Messages msg -> Model -> Element msg
arrowInputClearButton lang messages model =
    btn (t lang i18nClearArrows)
        |> withMsgIf (not <| List.isEmpty model.arrows) messages.clearArrows
        |> isEnabledIf (not <| List.isEmpty model.arrows)
        |> viewButton



--------------------------------------------------------------------------------
-- I18n Strings ----------------------------------------------------------------
--------------------------------------------------------------------------------


i18nNormalMode : I18nToken String
i18nNormalMode =
    I18nToken
        { english = "Normal Mode"
        , dutch = "Normale modus"
        , esperanto = "Normala reĝimo"
        }


i18nHighlight : I18nToken String
i18nHighlight =
    I18nToken
        { english = "Highlight"
        , dutch = "Markeer"
        , esperanto = "Markilo"
        }


i18nClearHighlight : I18nToken String
i18nClearHighlight =
    I18nToken
        { english = "Clear Highlight"
        , dutch = "Clear Markeer"
        , esperanto = "Forigi Markiloj"
        }


i18nArrows : I18nToken String
i18nArrows =
    I18nToken
        { english = "Arrows"
        , dutch = "Pijlen"
        , esperanto = "Sagoj"
        }


i18nClearArrows : I18nToken String
i18nClearArrows =
    I18nToken
        { english = "Clear Arrows"
        , dutch = "Clear Pijlen"
        , esperanto = "Forigi Sagoj"
        }
