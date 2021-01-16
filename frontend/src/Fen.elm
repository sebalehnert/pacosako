module Fen exposing (parseFen, writeFen)

{-| This module implements an extension of X-Fen that can represent settled Paco
Ŝako boards (i.e. boards without an active chain) together with most state.

It should be mostly compatible with <https://vchess.club/#/variants/Pacosako>
where I got the union notation. There are somewhat different pawn rules on the
vchess.club version, which explains the difference.

Fen looks like this:

    bqnrkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/NRBKRBNQ w 2 bedh -
    <pieces on board> <controlling player> <move count> <castling> <en passant> <union move>

The extension by vchess are:

  - A bitstring with 16 entries, one for each pawn column and color if the player
    already moved their pawn in this column. (Only allowed once on vchess)
  - The last pair move (if any), as undoing the same move directly is forbidden.

For compatibility we also include the <union move> as our fen could not be read
by the vchess page otherwise - even though we don't implement the ko rule.

-}

import List.Extra as List
import Sako exposing (Color(..), Piece, Tile(..), Type(..))



--------------------------------------------------------------------------------
-- Reading FEN -----------------------------------------------------------------
--------------------------------------------------------------------------------


type alias PiecesOnTile =
    { white : Maybe Sako.Type, black : Maybe Sako.Type }


flipColorsConditional : Char -> Maybe PiecesOnTile -> Maybe PiecesOnTile
flipColorsConditional char pieces =
    case ( Char.isLower char, pieces ) of
        ( False, Just { white, black } ) ->
            Just { white = black, black = white }

        _ ->
            pieces


{-| Takes a lower case character and returns which piece(s) this represents.
Use an uppercase letter to flip black and white.
-}
piecesOnTile : Char -> Maybe PiecesOnTile
piecesOnTile char =
    flipColorsConditional char <|
        case Char.toLower char of
            'p' ->
                Just { white = Nothing, black = Just Pawn }

            'r' ->
                Just { white = Nothing, black = Just Rook }

            'n' ->
                Just { white = Nothing, black = Just Knight }

            'b' ->
                Just { white = Nothing, black = Just Bishop }

            'q' ->
                Just { white = Nothing, black = Just Queen }

            'k' ->
                Just { white = Nothing, black = Just King }

            'a' ->
                Just { black = Just Pawn, white = Just Pawn }

            'c' ->
                Just { black = Just Pawn, white = Just Rook }

            'd' ->
                Just { black = Just Pawn, white = Just Knight }

            'e' ->
                Just { black = Just Pawn, white = Just Bishop }

            'f' ->
                Just { black = Just Pawn, white = Just Queen }

            'g' ->
                Just { black = Just Pawn, white = Just King }

            'h' ->
                Just { black = Just Rook, white = Just Rook }

            'i' ->
                Just { black = Just Rook, white = Just Knight }

            'j' ->
                Just { black = Just Rook, white = Just Bishop }

            'l' ->
                Just { black = Just Rook, white = Just Queen }

            'm' ->
                Just { black = Just Rook, white = Just King }

            'o' ->
                Just { black = Just Knight, white = Just Knight }

            's' ->
                Just { black = Just Knight, white = Just Bishop }

            't' ->
                Just { black = Just Knight, white = Just Queen }

            'u' ->
                Just { black = Just Knight, white = Just King }

            'v' ->
                Just { black = Just Bishop, white = Just Bishop }

            'w' ->
                Just { black = Just Bishop, white = Just Queen }

            'x' ->
                Just { black = Just Bishop, white = Just King }

            'y' ->
                Just { black = Just Queen, white = Just Queen }

            'z' ->
                Just { black = Just Queen, white = Just King }

            '_' ->
                Just { black = Just King, white = Just King }

            _ ->
                Nothing


{-| Given a string like "bqnrkb1r" or "3P4" this returns a list of 8 entries
which describe the pieces on each tile.
-}
parseRow : String -> List (Maybe PiecesOnTile)
parseRow string =
    String.toList string
        |> List.concatMap parseRowChar


parseRowChar : Char -> List (Maybe PiecesOnTile)
parseRowChar char =
    case String.toInt (String.fromChar char) of
        Just i ->
            -- if we find a number, we just repeat an empty tile.
            List.repeat i (Just { white = Nothing, black = Nothing })

        Nothing ->
            -- otherwise we try to read the char.
            [ piecesOnTile char ]


boardPart : String -> List (List (Maybe PiecesOnTile))
boardPart input =
    String.split "/" input
        |> List.map parseRow


buildPiece : Int -> Int -> Maybe PiecesOnTile -> List Sako.Piece
buildPiece rowId fileId pieces =
    let
        tile =
            Tile fileId (7 - rowId)
    in
    case pieces of
        Just { white, black } ->
            [ Maybe.map (buildColoredPiece tile Sako.White) white
            , Maybe.map (buildColoredPiece tile Sako.Black) black
            ]
                |> List.filterMap identity

        Nothing ->
            []


buildColoredPiece : Tile -> Color -> Type -> Piece
buildColoredPiece tile color pieceType =
    { pieceType = pieceType
    , color = color
    , position = tile
    , identity = ""
    }


assemblePieces : List (List (Maybe PiecesOnTile)) -> List Sako.Piece
assemblePieces lls =
    List.indexedMap
        (\rowId file ->
            List.indexedMap (\fileId pieces -> buildPiece rowId fileId pieces) file
        )
        lls
        |> List.concat
        |> List.concat


{-| Reads a string in X-Fen notation and converts it into a Paco Ŝako Position.
-}
parseFen : String -> Maybe Sako.Position
parseFen input =
    let
        parts =
            String.split " " input
    in
    List.getAt 0 parts
        |> Maybe.map (boardPart >> assemblePieces >> Sako.enumeratePieceIdentity)
        |> Maybe.map
            (\pieces ->
                { pieces = pieces
                , liftedPieces = []
                , currentPlayer = Sako.White
                }
            )



--------------------------------------------------------------------------------
-- Writing FEN -----------------------------------------------------------------
--------------------------------------------------------------------------------


{-| Writes X-Fen notation for the given Paco Ŝako position.

Right now, we don't track the current player nor the move counter so this
remains at some default values for now.

-}
writeFen : Sako.Position -> String
writeFen position =
    writeRows position.pieces ++ " w 0 ahah - -"


writeRows : List Sako.Piece -> String
writeRows pieces =
    [ 0, 1, 2, 3, 4, 5, 6, 7 ]
        |> List.map (writeRow pieces)
        |> String.join "/"


writeRow : List Sako.Piece -> Int -> String
writeRow pieces row =
    [ 0, 1, 2, 3, 4, 5, 6, 7 ]
        |> List.map (\file -> encodeTile pieces row file)
        |> List.map encodePiecesOnTile
        |> joinRow


encodeTile : List Sako.Piece -> Int -> Int -> PiecesOnTile
encodeTile allPieces row file =
    let
        localPieces =
            List.filter (Sako.isAt (Tile file (7 - row))) allPieces
    in
    { white = List.find (Sako.isColor White) localPieces |> Maybe.map .pieceType
    , black = List.find (Sako.isColor Black) localPieces |> Maybe.map .pieceType
    }


{-| Basically inverts piecesOnTile, but here the Maybe is not for error
handling, instead it signifies "this tile is empty".
-}
encodePiecesOnTile : PiecesOnTile -> Maybe Char
encodePiecesOnTile pot =
    case ( pot.white, pot.black ) of
        ( Nothing, Nothing ) ->
            Nothing

        ( Just white, Nothing ) ->
            encodeBlackPiece white |> Char.toUpper |> Just

        ( Nothing, Just black ) ->
            encodeBlackPiece black |> Just

        ( Just white, Just black ) ->
            encodePair black white |> Just


encodeBlackPiece : Sako.Type -> Char
encodeBlackPiece black =
    case black of
        Pawn ->
            'p'

        Rook ->
            'r'

        Knight ->
            'n'

        Bishop ->
            'b'

        Queen ->
            'q'

        King ->
            'k'


{-| Fetches the letter for a pair. Note that a symmetric pair will be written
with a capital letter by convention. (This is how vchess does it as well.)
-}
encodePair : Sako.Type -> Sako.Type -> Char
encodePair black white =
    case ( black, white ) of
        ( Pawn, Pawn ) ->
            'a' |> Char.toUpper

        ( Pawn, Rook ) ->
            'c'

        ( Pawn, Knight ) ->
            'd'

        ( Pawn, Bishop ) ->
            'e'

        ( Pawn, Queen ) ->
            'f'

        ( Pawn, King ) ->
            'g'

        ( Rook, Rook ) ->
            'h' |> Char.toUpper

        ( Rook, Knight ) ->
            'i'

        ( Rook, Bishop ) ->
            'j'

        ( Rook, Queen ) ->
            'l'

        ( Rook, King ) ->
            'm'

        ( Knight, Knight ) ->
            'o' |> Char.toUpper

        ( Knight, Bishop ) ->
            's'

        ( Knight, Queen ) ->
            't'

        ( Knight, King ) ->
            'u'

        ( Bishop, Bishop ) ->
            'v' |> Char.toUpper

        ( Bishop, Queen ) ->
            'w'

        ( Bishop, King ) ->
            'x'

        ( Queen, Queen ) ->
            'y' |> Char.toUpper

        ( Queen, King ) ->
            'z'

        ( King, King ) ->
            '_'

        ( foo, bar ) ->
            encodePair bar foo |> Char.toUpper


{-| Takes a list like [-, -, -, 'p', 'U', -, -, 'K'] and turns it into "3pU2K".
Here I am using "-" as shorthand for Nothing.
-}
joinRow : List (Maybe Char) -> String
joinRow tiles =
    List.foldl joinRowFoldStep { out = "", count = 0 } tiles
        |> terminateEmptySequence
        |> .out


joinRowFoldStep : Maybe Char -> { out : String, count : Int } -> { out : String, count : Int }
joinRowFoldStep mChar acc =
    case mChar of
        Nothing ->
            { acc | count = acc.count + 1 }

        Just char ->
            { acc
                | count = 0
                , out =
                    (terminateEmptySequence acc).out ++ String.fromChar char
            }


{-| If there is currently a count, add a number to the string and then set the
count back to 0. Does nothing if the count is 0.
-}
terminateEmptySequence : { out : String, count : Int } -> { out : String, count : Int }
terminateEmptySequence acc =
    { acc
        | count = 0
        , out =
            if acc.count > 0 then
                acc.out ++ String.fromInt acc.count

            else
                acc.out
    }
