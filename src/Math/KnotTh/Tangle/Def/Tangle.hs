{-# LANGUAGE TemplateHaskell #-}
module Math.KnotTh.Tangle.Def.Tangle
    ( module Math.KnotTh.Knotted
    , Dart
    , Crossing
    , Tangle
    , crossingTangle
    , dartTangle
    , numberOfLegs
    , isLeg
    , legPlace
    , nthLeg
    , allLegs
    , glueToBorder
    , changeNumberOfFreeLoops
    , implode
    , explode
    ) where

import Language.Haskell.TH
import Data.List (intercalate, nub, sort, foldl')
import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Array.Base (unsafeAt, unsafeWrite)
import Data.Array.ST (STArray, STUArray, newArray_)
import Data.Array.Unsafe (unsafeFreeze)
import Control.Monad.ST (ST, runST)
import Control.Monad (forM_, when)
import Text.Printf
import Math.KnotTh.Knotted.TH.Knotted
import Math.KnotTh.Knotted.TH.Show
import Math.KnotTh.Knotted


produceKnotted
    [d| data Tangle ct = Tangle { numberOfLegs :: {-# UNPACK #-} !Int } |] $
    let numberOfLegs = varE $ mkName "numberOfLegs"
        dart = conE $ mkName "Dart"
    in defaultKnotted
        { implodeExplodeSettings = Just $
            let l = mkName "l"
                brd = mkName "brd"
            in defaultImplodeExplode
                { extraImplodeParams  =
                    [ (brd, [t| [(Int, Int)] |], \ knot -> [| map (toPair . opposite) $ $(varE $ mkName "allLegs") $(knot) |])
                    ]

                , extraPairCases      =
                    [ \ n c p ->
                        ([| $c == (0 :: Int) |],
                            [|  if $p >= (0 :: Int) && $p < $(varE l)
                                    then 4 * $n + $p :: Int
                                    else error $ printf "Tangle.implode: leg index %i is out of bound" $p
                            |])
                    ]

                , modifyImplodeLimit  = Just $ \ n _ -> [| 4 * $n + $(varE l) - 1 :: Int |]

                , implodePreExtra     =
                    [ letS $ (:[]) $ valD (varP l) (normalB [| length $(varE brd) |]) []
                    , noBindS
                        [|  when (odd ($(varE l) :: Int)) $ fail $
                                printf "Tangle.implode: number of legs must be even (%i)" $(varE l)
                        |]
                    ]

                , implodePostExtra    =
                    [ \ n spliceFill -> noBindS
                        [|  forM_ (zip $(varE brd) [0 :: Int ..]) $ \ ((!c, !p), !i) ->
                                let a = 4 * $n + i
                                in $(spliceFill [| a |] ([| c |], [| p |]))
                        |]
                    ]

                , implodeInitializers =
                    [ (,) (mkName "numberOfLegs") `fmap` varE l
                    ]
                }

        , modifyNumberOfEdges = Just $ \ t _ ->
            [| 2 * (numberOfCrossings $(t)) + ($(numberOfLegs) $(t) `div` 2) |]

        , modifyIsDart = Just $ \ (t, i) ->
            [| $(i) < 4 * numberOfCrossings $(t) |]

        , modifyNextCCW = Just $ \ (t, d) e ->
            [|  let n = 4 * numberOfCrossings $(t)
                in if $(d) >= n
                    then $(dart) $(t) $! n + ($(d) - n + 1) `mod` ($(numberOfLegs) $(t))
                    else $(e)
            |]

        , modifyNextCW = Just $ \ (t, d) e ->
            [|  let n = 4 * numberOfCrossings $(t)
                in if $(d) >= n
                    then $(dart) $(t) $! n + ($(d) - n - 1) `mod` ($(numberOfLegs) $(t))
                    else $(e)
            |]

        , modifyDartPlace = Just $ \ (t, d) e ->
            [|  let n = 4 * numberOfCrossings $(t)
                in if $(d) >= n
                    then error $ printf "dartPlace: taken from %i-th leg" ($(d) - n)
                    else $(e)
            |]

        , modifyIncidentCrossing = Just $ \ (t, d) e ->
            [|  let n = 4 * numberOfCrossings $(t)
                in if $(d) >= n
                    then error $ printf "incidentCrossing: taken from %i-th leg" ($(d) - n)
                    else $(e)
            |]

        , modifyFoldMIncidentDartsFrom = Just $ \ (d, _) e ->
            [|  if isDart $(d)
                    then $(e)
                    else error $ printf "foldMIncidentDartsFrom: taken from leg %i"
                        ($(varE $ mkName "legPlace") $(d))
            |]
        }


{-# INLINE isLeg #-}
isLeg :: Dart ct -> Bool
isLeg = not . isDart


{-# INLINE legPlace #-}
legPlace :: Dart ct -> Int
legPlace d@(Dart t i)
    | isDart d   = error $ printf "legPlace: taken from non-leg %s" $ show d
    | otherwise  = i - 4 * numberOfCrossings t


{-# INLINE nthLeg #-}
nthLeg :: Tangle ct -> Int -> Dart ct
nthLeg t i =
    let n = 4 * numberOfCrossings t
        l = numberOfLegs t
    in Dart t $! n + i `mod` l


{-# INLINE allLegs #-}
allLegs :: Tangle ct -> [Dart ct]
allLegs t =
    let n = 4 * numberOfCrossings t
        l = numberOfLegs t
    in map (Dart t) [n .. n + l - 1]


--       edgesToGlue = 1                 edgesToGlue = 2                 edgesToGlue = 3
-- ........|                       ........|                       ........|
-- (leg+1)-|---------------3       (leg+1)-|---------------2       (leg+1)-|---------------1
--         |  +=========+                  |  +=========+                  |  +=========+
--  (leg)--|--|-0-\ /-3-|--2        (leg)--|--|-0-\ /-3-|--1        (leg)--|--|-0-\ /-3-|--0
-- ........|  |    *    |                  |  |    *    |                  |  |    *    |
-- ........|  |   / \-2-|--1       (leg-1)-|--|-1-/ \-2-|--0       (leg-1)-|--|-1-/ \   |
-- ........|  |  1      |          ........|  +=========+                  |  |      2  |
-- ........|  |   \-----|--0       ........|                       (leg-2)-|--|-----/   |
-- ........|  +=========+          ........|                       ........|  +=========+
glueToBorder :: (CrossingType ct) => Dart ct -> Int -> CrossingState ct -> Crossing ct
glueToBorder leg legsToGlue crossingToGlue
    | not (isLeg leg)                   = error $ printf "glueToBorder: leg expected, but %s received" (show leg)
    | legsToGlue < 0 || legsToGlue > 4  = error $ printf "glueToBorder: legsToGlue must be in [0 .. 4], but %i found" legsToGlue
    | otherwise                         = runST $ do
        let tangle = dartTangle leg
        let oldL = numberOfLegs tangle
        when (oldL < legsToGlue) $ fail $
            printf "glueToBorder: not enough legs to glue (l = %i, legsToGlue = %i)" oldL legsToGlue

        let oldC = numberOfCrossings tangle
        let newC = oldC + 1
        let newL = oldL + 4 - 2 * legsToGlue
        let lp = legPlace leg

        cr <- newArray_ (0, 4 * newC + newL - 1) :: ST s (STUArray s Int Int)

        let {-# INLINE copyModified #-}
            copyModified !index !index' = do
                let y | x < 4 * oldC            = x
                      | ml < oldL - legsToGlue  = 4 * newC + 4 - legsToGlue + ml
                      | otherwise               = 4 * newC - 5 + oldL - ml
                      where
                          x = crossArray tangle `unsafeAt` index' 
                          ml = (x - 4 * oldC - lp - 1) `mod` oldL
                unsafeWrite cr index y

        forM_ [0 .. 4 * oldC - 1] $ \ !i ->
            copyModified i i

        forM_ [0 .. legsToGlue - 1] $ \ !i ->
            copyModified (4 * (newC - 1) + i) (4 * oldC + ((lp - i) `mod` oldL))

        forM_ [0 .. 3 - legsToGlue] $ \ !i -> do
            let a = 4 * (newC - 1) + legsToGlue + i
            let b = 4 * newC + i
            unsafeWrite cr a b
            unsafeWrite cr b a

        forM_ [0 .. oldL - 1 - legsToGlue] $ \ !i ->
            copyModified (4 * newC + i + 4 - legsToGlue) (4 * oldC + ((lp + 1 + i) `mod` oldL))

        st <- newArray_ (0, newC - 1) :: ST s (STArray s Int a)
        forM_ [0 .. oldC - 1] $ \ !i ->
            unsafeWrite st i $! stateArray tangle `unsafeAt` i
        unsafeWrite st (newC - 1) crossingToGlue

        cr' <- unsafeFreeze cr
        st' <- unsafeFreeze st
        let result = Tangle
                { loopsCount   = numberOfFreeLoops tangle
                , crossCount   = newC
                , crossArray   = cr'
                , stateArray   = st' 
                , numberOfLegs = newL
                }

        return $! nthCrossing result newC


instance Show (Dart ct) where
    show d
        | isLeg d    = printf "(Leg %i)" $ legPlace d
        | otherwise  =
            let (c, p) = toPair d
            in printf "(Dart %i %i)" c p


produceShowCrossing ''Crossing


instance (CrossingType ct) => Show (Tangle ct) where
    show tangle =
        let border = printf "(Border [ %s ])" $
                intercalate " " $ map (show . opposite) $ allLegs tangle
        in printf "(Tangle (%i O) %s)"
            (numberOfFreeLoops tangle)
            (intercalate " " $ border : map show (allCrossings tangle))


instance KnottedWithToPair Tangle Crossing Dart where
    toPair d
        | isLeg d    =
            let p = legPlace d
            in p `seq` (0, p)
        | otherwise  =
            let c = crossingIndex $ incidentCrossing d
                p = dartPlace d
            in c `seq` p `seq` (c, p)


instance KnottedWithConnectivity Tangle Crossing Dart where
    isConnected tangle
        | numberOfEdges tangle == 0 && numberOfFreeLoops tangle <= 1  = True
        | numberOfFreeLoops tangle /= 0                               = False
        | otherwise                                                   = all (\ (a, b) -> Set.member a con && Set.member b con) edges
        where
            edges = allEdges tangle
            con = dfs (Set.empty) $ fst $ head edges
            dfs vis c
                | Set.member c vis  = vis
                | otherwise         = foldl' dfs (Set.insert c vis) neigh
                where
                    neigh
                        | isLeg c    = [opposite c]
                        | otherwise  = [opposite c, nextCCW c, nextCW c]

    isPrime tangle = connections == nub connections
        where
            idm =    let faces = directedPathsDecomposition (nextCW, nextCCW)
                in Map.fromList $ concatMap (\ (face, i) -> zip face $ repeat i) $ zip faces [(0 :: Int) ..]

            connections = sort $ map getPair $ allEdges tangle
                where
                    getPair (da, db) = (min a b, max a b)
                        where
                            a = idm Map.! da
                            b = idm Map.! db

            directedPathsDecomposition continue = fst $ foldl' processDart ([], Set.empty) $ allHalfEdges tangle
                where
                    processDart (paths, s) d
                        | Set.member d s  = (paths, s)
                        | otherwise       = (path : paths, nextS)
                        where
                            path = containingDirectedPath continue d
                            nextS = foldl' (\ curs a -> Set.insert a curs) s path

            containingDirectedPath (adjForward, adjBackward) start
                | isCycle    = forward
                | otherwise  = walkBackward (start, forward)
                where
                    (forward, isCycle) = walkForward start

                    walkForward d
                        | isLeg opp     = ([d], False)
                        | start == nxt  = ([d], True)
                        | otherwise     = (d : nextPath, nextCycle)
                        where
                            opp = opposite d
                            nxt = adjForward opp
                            (nextPath, nextCycle) = walkForward nxt

                    walkBackward (d, path)
                        | isLeg d    = path
                        | otherwise  = let prev = opposite $ adjBackward d in walkBackward (prev, prev : path)