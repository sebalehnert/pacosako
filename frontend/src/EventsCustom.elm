module EventsCustom exposing (BoardMousePosition, onEnter, svgDown, svgMove, svgUp)

{-| The default events we get for SVG graphics are a problem, because they are
using external coordinates. It is a lot easier to work with internal coordinates
of the svg, so we have introduces custom events.

This also implements an onEnter event attribute.

-}

import Element
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Sako exposing (Tile(..))
import Svg exposing (Attribute)
import Svg.Events


type alias BoardMousePosition =
    { x : Int
    , y : Int
    , tile : Maybe Tile
    }


boardMousePosition : Float -> Float -> BoardMousePosition
boardMousePosition x y =
    { x = round x
    , y = round y
    , tile = safeTileCoordinate (round x) (round y)
    }


{-| Transforms an Svg coordinate into a logical tile coordinte.
Returns Nothing, if the SvgCoordinate is outside the board.
-}
safeTileCoordinate : Int -> Int -> Maybe Tile
safeTileCoordinate x y =
    if 0 <= x && x < 800 && 0 <= y && y < 800 then
        Just (Tile (x // 100) (7 - y // 100))

    else
        Nothing


decodeBoardMousePosition : Decoder BoardMousePosition
decodeBoardMousePosition =
    Decode.map2 boardMousePosition
        (Decode.at [ "detail", "x" ] Decode.float)
        (Decode.at [ "detail", "y" ] Decode.float)


svgDown : (BoardMousePosition -> msg) -> Attribute msg
svgDown message =
    Svg.Events.on "svgdown" (Decode.map message decodeBoardMousePosition)


svgMove : (BoardMousePosition -> msg) -> Attribute msg
svgMove message =
    Svg.Events.on "svgmove" (Decode.map message decodeBoardMousePosition)


svgUp : (BoardMousePosition -> msg) -> Attribute msg
svgUp message =
    Svg.Events.on "svgup" (Decode.map message decodeBoardMousePosition)


{-| Event attribute that triggens when the element has focus and the user
presses the enter key. This is great for inputs that are not part of a larger
form and where just entering a single value has meaning.
-}
onEnter : msg -> Element.Attribute msg
onEnter msg =
    Element.htmlAttribute
        (Html.Events.on "keyup"
            (Decode.field "key" Decode.string
                |> Decode.andThen
                    (\key ->
                        if key == "Enter" then
                            Decode.succeed msg

                        else
                            Decode.fail "Not the enter key"
                    )
            )
        )
