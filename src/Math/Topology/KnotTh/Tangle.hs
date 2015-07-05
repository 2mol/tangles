{-# LANGUAGE TypeFamilies, UnboxedTuples, RankNTypes, GeneralizedNewtypeDeriving #-}
module Math.Topology.KnotTh.Tangle
    ( module Math.Topology.KnotTh.Knotted
    , module Math.Topology.KnotTh.Knotted.Crossings.Projection
    , module Math.Topology.KnotTh.Knotted.Crossings.Diagram
    , TangleLike(..)
    , (|=|)
    , (⊗)
    , identityBraidTangle
    , braidGeneratorTangle
    , braidTangle
    , reversingBraidTangle
    , gridTangle
    , chainTangle
    , lonerProjection
    , lonerOverCrossing
    , lonerUnderCrossing
    , rationalTangle
    , twistedDoubleSatellite
    , twistedTripleSatellite
    , Tangle
    , TangleProjection
    , TangleProjectionVertex
    , TangleProjectionDart
    , TangleDiagram
    , TangleDiagramVertex
    , TangleDiagramDart
    , ProjectionPattern(..)
    , DiagramPattern(..)
    , CascadeCodePattern(..)
    , decodeCascadeCode
    , decodeCascadeCodeFromPairs
    ) where

import Control.Applicative (Applicative)
import Control.DeepSeq (NFData(..))
import Control.Monad (void, forM, forM_, when, unless, foldM_, foldM, filterM, (>=>), guard)
import qualified Control.Monad.ST as ST
import qualified Control.Monad.Reader as Reader
import qualified Data.Array.Unboxed as A
import Data.Bits ((.&.), complement, shiftL, shiftR)
import Data.Char (isSpace)
import Data.List (nub, sort, foldl', find)
import Data.Maybe (fromMaybe)
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.STRef as STRef
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import qualified Data.Vector.Unboxed as UV
import qualified Data.Vector.Unboxed.Mutable as UMV
import qualified Data.Vector.Primitive as PV
import qualified Data.Vector.Primitive.Mutable as PMV
import Text.Printf
import Math.Topology.KnotTh.Dihedral.D4
import Math.Topology.KnotTh.Dihedral.Dn
import Math.Topology.KnotTh.Knotted
import Math.Topology.KnotTh.Knotted.Crossings.Projection
import Math.Topology.KnotTh.Knotted.Crossings.Diagram
import Math.Topology.KnotTh.Knotted.Threads
import Math.Topology.KnotTh.Moves.ModifyDSL


class (KnottedPlanar t, PlanarAlgebra t) => TangleLike t where
    emptyTangle :: t a
    emptyTangle = emptyKnotted

    -- | 2--1
    --   3--0
    zeroTangle     :: t a

    -- | 2   1
    --   |   |
    --   3   0
    infinityTangle :: t a

    -- | +-------+
    --   |   ^   |
    --   |   |   |
    --   |   |   |
    --   +-------+
    identityTangle :: t a

    lonerTangle :: a -> t a

    rotateTangle     :: Int -> t a -> t a
    mirrorTangleWith :: (a -> a) -> t a -> t a
    mirrorTangle     :: (Crossing a) => t a -> t a

    mirrorTangle = mirrorTangleWith mirrorCrossing

    -- |           legsToGlue = 2
    --  ..............|
    --  (legA + 2) ---|- 0
    --  ..............|     |..............
    --  (legA + 1) ---|-----|--- (legB - 1)
    --  ..............|     |..............
    --  (legA) -------|-----|--- (legB)
    --  ..............|     |..............
    glueTangles :: Int -> Dart t a -> Dart t a -> t a

    -- |     edgesToGlue = 1                 edgesToGlue = 2                 edgesToGlue = 3
    -- ........|                       ........|                       ........|
    -- (leg+1)-|---------------3       (leg+1)-|---------------2       (leg+1)-|---------------1
    --         |  +=========+                  |  +=========+                  |  +=========+
    --  (leg)--|--|-0-\ /-3-|--2        (leg)--|--|-0-\ /-3-|--1        (leg)--|--|-0-\ /-3-|--0
    -- ........|  |    *    |                  |  |    *    |                  |  |    *    |
    -- ........|  |   / \-2-|--1       (leg-1)-|--|-1-/ \-2-|--0       (leg-1)-|--|-1-/ \   |
    -- ........|  |  1      |          ........|  +=========+                  |  |      2  |
    -- ........|  |   \-----|--0       ........|                       (leg-2)-|--|-----/   |
    -- ........|  +=========+          ........|                       ........|  +=========+
    glueToBorder :: Dart t a -> Int -> a -> Vertex t a

    tensorSubst :: Int -> (Vertex t a -> t b) -> t a -> t b


(|=|) :: (TangleLike t) => t a -> t a -> t a
(|=|) a b | al /= bl   = error $ printf "braidLikeGlue: different numbers of legs (%i and %i)" al bl
          | otherwise  = glueTangles n (nthLeg a n) (nthLeg b (n - 1))
    where
        al = numberOfLegs a
        bl = numberOfLegs b
        n = al `div` 2


(⊗) :: (TangleLike t) => t a -> t a -> t a
(⊗) a b =
    let k = numberOfLegs a `div` 2
    in rotateTangle (-k) $ glueTangles 0 (nthLeg a k) (firstLeg b)


instance RotationAction (Tangle a) where
    rotationOrder = numberOfLegs
    rotate        = rotateTangle

instance (Crossing a) => DihedralAction (Tangle a) where
    mirror = mirrorTangle

instance (Crossing a) => GroupAction (Tangle a) where
    type TransformGroup (Tangle a) = Dn

    transform g tangle | l /= l'       = error $ printf "transformTangle: order conflict: %i legs, %i order of group" l l'
                       | reflection g  = mirrorTangle $ rotateTangle (rotation g) tangle
                       | otherwise     = rotateTangle (rotation g) tangle
        where
            l = numberOfLegs tangle
            l' = pointsUnderGroup g


identityBraidTangle :: Int -> Tangle a
identityBraidTangle n
    | n < 0      = error $ printf "identityBraidTangle: requested number of strands %i is negative" n
    | otherwise  =
        let n' = 2 * n - 1
        in implode (0, [(0, n' - i) | i <- [0 .. n']], [])


braidGeneratorTangle :: Int -> (Int, a) -> Tangle a
braidGeneratorTangle n (k, s)
    | n < 2               = error $ printf "braidGeneratorTangle: braid must have at least 2 strands, but %i requested" n
    | k < 0 || k > n - 2  = error $ printf "braidGeneratorTangle: generator offset %i is out of bounds (0, %i)" k (n - 2)
    | otherwise           =
        let n' = 2 * n - 1
            k' = n' - k - 1
            b = map $ \ i -> (0, n' - i)
        in implode
            ( 0
            , concat [b [0 .. k - 1], [(1, 0), (1, 1)], b [k + 2 .. k' - 1], [(1, 2), (1, 3)], b [k' + 2 .. n']]
            , [([(0, k), (0, k + 1), (0, k'), (0, k' + 1)], s)]
            )


braidTangle :: Int -> [(Int, a)] -> Tangle a
braidTangle n = foldl (\ braid -> (braid |=|) . braidGeneratorTangle n) (identityBraidTangle n)


reversingBraidTangle :: Int -> a -> Tangle a
reversingBraidTangle n s
    | n < 0      = error $ printf "flipBraidTangle: requested number of strands %i is negative" n
    | otherwise  = braidTangle n [ (i, s) | k <- [2 .. n], i <- [0 .. n - k] ]


gridTangle :: (Int, Int) -> ((Int, Int) -> a) -> Tangle a
gridTangle (n, m) f
    | n < 0      = error $ printf "gridTangle: first dimension %i is negative" n
    | m < 0      = error $ printf "gridTangle: second dimension %i is negative" m
    | otherwise  =
        let border = ([1 .. n] `zip` repeat 0) ++ (map (\ i -> n * i) [1 .. m] `zip` repeat 1)
                ++ (map (\ i -> n * m + 1 - i) [1 .. n] `zip` repeat 2)
                ++ (map (\ i -> (m - i) * n + 1) [1 .. m] `zip` repeat 3)

            body = do
                j <- [1 .. m]
                i <- [1 .. n]
                return (
                    [ if j > 1 then (n * (j - 2) + i    , 2) else (0, i - 1            )
                    , if i < n then (n * (j - 1) + i + 1, 3) else (0, j + n - 1        )
                    , if j < m then (n * j + i          , 0) else (0, 2 * n + m - i    )
                    , if i > 1 then (n * (j - 1) + i - 1, 1) else (0, 2 * m + 2 * n - j)
                    ], f (i, j))
        in implode (0, border, body)


chainTangle :: [a] -> Tangle a
chainTangle [] = zeroTangle
chainTangle list =
    let n = length list
    in implode
        ( 0
        , [(1, 0), (1, 1), (n, 2), (n, 3)]
        , map (\ (i, s) ->
            (   [ if i > 1 then (i - 1, 3) else (0, 0)
                , if i > 1 then (i - 1, 2) else (0, 1)
                , if i < n then (i + 1, 1) else (0, 2)
                , if i < n then (i + 1, 0) else (0, 3)
                ]
            , s
            )) ([1 .. n] `zip` list)
        )


lonerProjection :: TangleProjection
lonerProjection = lonerTangle projectionCrossing


lonerOverCrossing, lonerUnderCrossing :: TangleDiagram
lonerOverCrossing = lonerTangle overCrossing
lonerUnderCrossing = lonerTangle underCrossing


rationalTangle :: [Int] -> TangleDiagram
rationalTangle = flip foldl infinityTangle $ \ tangle x ->
    let g = chainTangle $ replicate (abs x) (if x >= 0 then overCrossing else underCrossing)
    in glueTangles 2 (nthLeg g 2) (nthLeg tangle 2)


twistedDoubleSatellite :: TangleDiagram -> TangleDiagram
twistedDoubleSatellite = twistedNSatellite 2


twistedTripleSatellite :: TangleDiagram -> TangleDiagram
twistedTripleSatellite = twistedNSatellite 3


twistedNSatellite :: Int -> TangleDiagram -> TangleDiagram
twistedNSatellite n tangle
    | n < 0      = error "twistedNSattelite: negative order"
    | n == 0     = emptyTangle
    | n == 1     = tangle
    | otherwise  = tensorSubst n wrap tangle
    where
        w = selfWritheArray tangle

        wrap v | wc == 0    = cross
               | otherwise  =
                   let r | wc > 0     = underCrossing
                         | otherwise  = overCrossing

                       braid =
                           let half = reversingBraidTangle n r
                           in half |=| half
                   in glueTangles n (nthLeg braid n) (nthLeg cross $ n - 1)
            where
                wc = w A.! v
                s = vertexCrossing v
                cross = gridTangle (n, n) (const s)




data Tangle a =
    Tangle
        { loopsCount      :: {-# UNPACK #-} !Int
        , vertexCount     :: {-# UNPACK #-} !Int
        , involutionArray :: {-# UNPACK #-} !(PV.Vector Int)
        , crossingsArray  :: {-# UNPACK #-} !(V.Vector a)
        , legsCount       :: {-# UNPACK #-} !Int
        }


instance PlanarDiagram Tangle where
    numberOfVertices = vertexCount

    numberOfEdges t = PV.length (involutionArray t) `shiftR` 1

    numberOfDarts t = PV.length (involutionArray t)

    nthVertex t i | i < 1 || i > b  = error $ printf "nthVertex: index %i is out of bounds [1, %i]" i b
                  | otherwise       = Vertex t (i - 1)
        where
             b = numberOfVertices t

    nthDart t i | i < 0 || i >= b  = error $ printf "nthDart: index %i is out of bounds [0, %i)" i b
                | otherwise        = Dart t i
        where
            b = PV.length (involutionArray t)

    allVertices t = map (Vertex t) [0 .. numberOfVertices t - 1]

    allHalfEdges t = map (Dart t) [0 .. PV.length (involutionArray t) - 1]

    allEdges t =
        foldl' (\ !es !i ->
                let j = involutionArray t `PV.unsafeIndex` i
                in if i < j
                    then (Dart t i, Dart t j) : es
                    else es
            ) [] [0 .. PV.length (involutionArray t) - 1]

    data Vertex Tangle a = Vertex !(Tangle a) {-# UNPACK #-} !Int

    vertexDegree _ = 4
    vertexOwner (Vertex t _) = t
    vertexIndex (Vertex _ i) = i + 1

    nthOutcomingDart (Vertex t c) i = Dart t ((c `shiftL` 2) + (i .&. 3))

    outcomingDarts c = map (nthOutcomingDart c) [0 .. 3]

    data Dart Tangle a = Dart !(Tangle a) {-# UNPACK #-} !Int

    dartOwner (Dart t _) = t
    dartIndex (Dart _ i) = i

    opposite (Dart t d) = Dart t (involutionArray t `PV.unsafeIndex` d)

    beginVertex (Dart t d) | d >= n     = error $ printf "beginVertex: taken from %i-th leg" (d - n)
                           | otherwise  = Vertex t (d `shiftR` 2)
        where
            n = vertexCount t `shiftL` 2

    beginPlace (Dart t d) | d >= n     = error $ printf "beginPlace: taken from %i-th leg" (d - n)
                          | otherwise  = d .&. 3
        where
            n = vertexCount t `shiftL` 2

    beginPair' d | isDart d   = (vertexIndex $ beginVertex d, beginPlace d)
                 | otherwise  = (0, legPlace d)

    nextCCW (Dart t d) | d >= n     = Dart t (n + (d - n + 1) `mod` legsCount t)
                       | otherwise  = Dart t ((d .&. complement 3) + ((d + 1) .&. 3))
        where
            n = vertexCount t `shiftL` 2

    nextCW (Dart t d) | d >= n     = Dart t (n + (d - n - 1) `mod` legsCount t)
                      | otherwise  = Dart t ((d .&. complement 3) + ((d - 1) .&. 3))
        where
            n = vertexCount t `shiftL` 2

    isDart (Dart t i) = i < (vertexCount t `shiftL` 2)

    vertexIndicesRange t = (1, numberOfVertices t)

    dartIndicesRange t = (0, numberOfDarts t - 1)


instance (NFData a) => NFData (Tangle a) where
    rnf t = rnf (crossingsArray t) `seq` t `seq` ()

instance (NFData a) => NFData (Vertex Tangle a)

instance (NFData a) => NFData (Dart Tangle a)


instance Functor Tangle where
    fmap f t = t { crossingsArray = f `fmap` crossingsArray t }


instance Knotted Tangle where
    vertexCrossing (Vertex t i) = crossingsArray t `V.unsafeIndex` i

    mapCrossings f t =
        t { crossingsArray =
                V.generate (numberOfVertices t) $ \ i -> f (nthVertex t $ i + 1)
          }

    unrootedHomeomorphismInvariant tangle
        | n > 127    = error $ printf "unrootedHomeomorphismInvariant: too many crossings (%i)" n
        | otherwise  = UV.concat $ UV.singleton (numberOfFreeLoops tangle) : border : internal
        where
            n = numberOfVertices tangle
            l = numberOfLegs tangle

            border | l == 0    = UV.empty
                   | otherwise = minimum $ do
                leg <- allLegs tangle
                dir <- bothDirections
                globalG <- fromMaybe [d4I] $ globalTransformations tangle

                return $! UV.create $ do
                    index <- UMV.replicate (n + 1) 0
                    queue <- MV.new n
                    free <- STRef.newSTRef 1

                    let {-# INLINE look #-}
                        look !d | isLeg d    = return 0
                                | otherwise  = do
                            let u = beginVertex d
                            ux <- UMV.read index (vertexIndex u)
                            if ux > 0
                                then return $! ux
                                else do
                                    nf <- STRef.readSTRef free
                                    STRef.writeSTRef free $! nf + 1
                                    UMV.write index (vertexIndex u) nf
                                    MV.write queue (nf - 1) d
                                    return $! nf

                    rc <- UMV.new (l + 2 * n)
                    foldM_ (\ !d !i -> do
                            look (opposite d) >>= UMV.write rc i
                            return $! nextDir dir d
                        ) leg [0 .. l - 1]

                    let {-# INLINE lookAndAdd #-}
                        lookAndAdd !d !s = do
                            !c <- look d
                            return $! c + (s `shiftL` 7)

                        bfs !headI = do
                            tailI <- STRef.readSTRef free
                            when (headI < tailI - 1) $ do
                                input <- MV.read queue headI
                                !nb <- foldMAdjacentDartsFrom input dir lookAndAdd 0
                                case crossingCodeWithGlobal globalG dir input of
                                    (# be, le #) -> do
                                        let offset = l + headI `shiftL` 1
                                        UMV.write rc offset be
                                        UMV.write rc (offset + 1) (le + nb `shiftL` 3)
                                        bfs (headI + 1)

                    bfs 0
                    tailI <- STRef.readSTRef free
                    return $ UMV.take (l + 2 * (tailI - 1)) rc

            internal | UV.length border >= (l + 2 * n)  = []
                     | otherwise                        = sort $ map compCode comps
                where
                    comps = ST.runST $ do
                        visited <- UMV.replicate (n + 1) (-1)
                        let dfs mark v = do
                                vis <- UMV.read visited (vertexIndex v)
                                when (vis < 0) $ do
                                    UMV.write visited (vertexIndex v) mark
                                    forMAdjacentDarts v $ \ !d ->
                                        when (isDart d) (dfs mark $ beginVertex d)

                        forM_ (allLegOpposites tangle) $ \ !d ->
                            when (isDart d) (dfs 0 $ beginVertex d)

                        c <- foldM (\ !ci !v -> do
                                vis <- UMV.read visited (vertexIndex v)
                                if vis < 0
                                    then dfs ci v >> return (ci + 1)
                                    else return ci
                            ) 1 (allVertices tangle)

                        lists <- MV.replicate c []
                        forM_ (allVertices tangle) $ \ !v -> do
                            ci <- UMV.read visited (vertexIndex v)
                            lst <- MV.read lists ci
                            MV.write lists ci (v : lst)

                        mapM (MV.read lists) [1 .. c - 1]

                    compCode comp = minimum $ do
                        start <- comp
                        root <- outcomingDarts start
                        dir <- bothDirections
                        globalG <- fromMaybe [d4I] $ globalTransformations tangle

                        return $! UV.create $ do
                            index <- UMV.replicate (n + 1) 0
                            queue <- MV.new n
                            free <- STRef.newSTRef 1

                            let {-# INLINE look #-}
                                look !d = do
                                    let u = beginVertex d
                                    ux <- UMV.read index (vertexIndex u)
                                    if ux > 0
                                        then return $! ux
                                        else do
                                            nf <- STRef.readSTRef free
                                            STRef.writeSTRef free $! nf + 1
                                            UMV.write index (vertexIndex u) nf
                                            MV.write queue (nf - 1) d
                                            return $! nf

                            rc <- UMV.new (2 * n)
                            void $ look root

                            let {-# INLINE lookAndAdd #-}
                                lookAndAdd !d !s = do
                                    !c <- look d
                                    return $! c + (s `shiftL` 7)

                                bfs !headI = do
                                    tailI <- STRef.readSTRef free
                                    when (headI < tailI - 1) $ do
                                        input <- MV.read queue headI
                                        !nb <- foldMAdjacentDartsFrom input dir lookAndAdd 0
                                        case crossingCodeWithGlobal globalG dir input of
                                            (# be, le #) -> do
                                                let offset = headI `shiftL` 1
                                                UMV.write rc offset be
                                                UMV.write rc (offset + 1) (le + nb `shiftL` 3)
                                                bfs (headI + 1)

                            bfs 0
                            tailI <- STRef.readSTRef free
                            return $ UMV.take (2 * (tailI - 1)) rc

    isConnected tangle
        | numberOfEdges tangle == 0 && numberOfFreeLoops tangle <= 1  = True
        | numberOfFreeLoops tangle /= 0                               = False
        | otherwise                                                   = all (\ (a, b) -> S.member a con && S.member b con) edges
        where
            edges = allEdges tangle
            con = dfs S.empty $ fst $ head edges
            dfs vis c | S.member c vis  = vis
                      | otherwise       = foldl' dfs (S.insert c vis) neigh
                where
                    neigh | isLeg c    = [opposite c]
                          | otherwise  = [opposite c, nextCCW c, nextCW c]

    type ExplodeType Tangle a = (Int, [(Int, Int)], [([(Int, Int)], a)])

    explode tangle =
        ( numberOfFreeLoops tangle
        , map endPair' $ allLegs tangle
        , map (\ v -> (map endPair' $ outcomingDarts v, vertexCrossing v)) $ allVertices tangle
        )

    implode (loops, brd, list) = ST.runST $ do
        when (loops < 0) $
            error $ printf "Tangle.implode: number of free loops %i is negative" loops

        let l = length brd
        when (odd l) $
            error $ printf "Tangle.implode: number of legs %i must be even" l

        let n = length list
        cr <- PMV.new (4 * n + l)
        st <- MV.new n

        let {-# INLINE write #-}
            write !a !c !p = do
                let b | c == 0 && p >= 0 && p < l  = 4 * n + p
                      | c == 0                     = error $ printf "Tangle.implode: leg index %i is out of bounds [0, %i)" p l
                      | c < 1 || c > n             = error $ printf "Tangle.implode: crossing index %i is out of bounds [1 .. %i]" c n
                      | p < 0 || p > 3             = error $ printf "Tangle.implode: place index %i is out of bounds [0 .. 3]" p
                      | otherwise                  = 4 * (c - 1) + p
                when (a == b) $ error $ printf "Tangle.implode: (%i, %i) connected to itself" c p
                PMV.unsafeWrite cr a b
                when (b < a) $ do
                    x <- PMV.unsafeRead cr b
                    when (x /= a) $ error $ printf "Tangle.implode: (%i, %i) points to unconsistent position" c p

        forM_ (list `zip` [0 ..]) $ \ ((!ns, !cs), !i) -> do
            MV.unsafeWrite st i cs
            case ns of
                [p0, p1, p2, p3] ->
                    forM_ [(p0, 0), (p1, 1), (p2, 2), (p3, 3)] $ \ ((!c, !p), !j) ->
                        write (4 * i + j) c p
                _                ->
                    error $ printf "Tangle.implode: there must be 4 neighbours for every crossing, but found %i for %i-th"
                                        (length ns) (i + 1)

        forM_ (brd `zip` [0 ..]) $ \ ((!c, !p), !i) ->
            write (4 * n + i) c p

        cr' <- PV.unsafeFreeze cr
        st' <- V.unsafeFreeze st

        return Tangle
            { loopsCount      = loops
            , vertexCount     = n
            , involutionArray = cr'
            , crossingsArray  = st'
            , legsCount       = l
            }


instance KnottedPlanar Tangle where
    numberOfFreeLoops = loopsCount

    changeNumberOfFreeLoops loops t | loops >= 0  = t { loopsCount = loops }
                                    | otherwise   = error $ printf "changeNumberOfFreeLoops: number of free loops %i is negative" loops

    emptyKnotted =
        Tangle
            { loopsCount      = 0
            , vertexCount     = 0
            , involutionArray = PV.empty
            , crossingsArray  = V.empty
            , legsCount       = 0
            }


instance KnottedDiagram Tangle where
    isReidemeisterReducible =
        any (\ ab ->
                let ba = opposite ab
                    ac = nextCCW ab
                in (ac == ba) || (isDart ba && passOver ab == passOver ba && opposite ac == nextCW ba)
            ) . allOutcomingDarts

    tryReduceReidemeisterI tangle =  do
        d <- find (\ d -> opposite d == nextCCW d) (allOutcomingDarts tangle)
        return $! modifyKnot tangle $ do
            let ac = nextCW d
                ab = nextCW ac
                ba = opposite ab
            substituteC [(ba, ac)]
            maskC [beginVertex d]

    tryReduceReidemeisterII tangle = do
        abl <- find (\ abl ->
                let bal = opposite abl
                    abr = nextCCW abl
                in isDart bal && passOver abl == passOver bal && opposite abr == nextCW bal
            ) (allOutcomingDarts tangle)

        return $! modifyKnot tangle $ do
            let bal = opposite abl

                ap = threadContinuation abl
                aq = nextCW abl
                br = nextCCW bal
                bs = threadContinuation bal

                pa = opposite ap
                qa = opposite aq
                rb = opposite br
                sb = opposite bs

            if qa == ap || rb == bs
                then if qa == ap && rb == bs
                    then emitLoopsC 1
                    else do
                        when (qa /= ap) $ connectC [(pa, qa)]
                        when (rb /= bs) $ connectC [(rb, sb)]
                else do
                    if qa == br
                        then emitLoopsC 1
                        else connectC [(qa, rb)]

                    if pa == bs
                        then emitLoopsC 1
                        else connectC [(pa, sb)]

            maskC [beginVertex abl, beginVertex bal]

    reidemeisterIII tangle = do
        ab <- allOutcomingDarts tangle

        -- \sc           /rb             \sc   /rb
        --  \           /                 \   /
        -- cs\ cb   bc /br               ac\ /ab
        -- ---------------                  /
        --   ca\c   b/ba                 ap/a\aq
        --      \   /         -->         /   \
        --     ac\ /ab                 cs/c   b\br
        --        /                  ---------------
        --     ap/a\aq               ca/ cb   bc \ba
        --      /   \                 /           \
        --   pa/     \qa             /pa           \qa
        guard $ isDart ab

        let ac = nextCCW ab
            ba = opposite ab
            ca = opposite ac

        guard $ isDart ba && isDart ca

        let bc = nextCW ba
            cb = nextCCW ca

        guard $ bc == opposite cb

        let a = beginVertex ab
            b = beginVertex ba
            c = beginVertex ca

        guard $ (a /= b) && (a /= c) && (b /= c)
        guard $ passOver bc == passOver cb

        guard $ let altRoot | passOver ab == passOver ba  = ca
                            | otherwise                   = bc
                in ab < altRoot

        let ap = threadContinuation ab
            aq = nextCW ab
            br = nextCW bc
            cs = nextCCW cb

        return $! modifyKnot tangle $ do
            substituteC [(ca, ap), (ba, aq), (ab, br), (ac, cs)]
            connectC [(br, aq), (cs, ap)]


instance PlanarAlgebra Tangle where
    numberOfLegs = legsCount

    nthLeg t i | l == 0     = error "nthLeg: tangle has no legs"
               | otherwise  = Dart t (n + i `mod` l)
        where
            l = numberOfLegs t
            n = vertexCount t `shiftL` 2

    allLegs t =
        let n = vertexCount t `shiftL` 2
            l = numberOfLegs t
        in map (Dart t) [n .. n + l - 1]

    legPlace d@(Dart t i) | isDart d   = error $ printf "legPlace: taken from non-leg %s" $ show d
                          | otherwise  = i - 4 * numberOfVertices t

    isLeg = not . isDart


instance TangleLike Tangle where
    zeroTangle =
        Tangle
            { loopsCount      = 0
            , vertexCount     = 0
            , involutionArray = PV.fromList [3, 2, 1, 0]
            , crossingsArray  = V.empty
            , legsCount       = 4
            }

    infinityTangle =
        Tangle
            { loopsCount      = 0
            , vertexCount     = 0
            , involutionArray = PV.fromList [1, 0, 3, 2]
            , crossingsArray  = V.empty
            , legsCount       = 4
            }

    identityTangle =
        Tangle
            { loopsCount      = 0
            , vertexCount     = 0
            , involutionArray = PV.fromList [1, 0]
            , crossingsArray  = V.empty
            , legsCount       = 2
            }

    lonerTangle cr =
        Tangle
            { loopsCount      = 0
            , vertexCount     = 1
            , involutionArray = PV.fromList [4, 5, 6, 7, 0, 1, 2, 3]
            , crossingsArray  = V.singleton cr
            , legsCount       = 4
            }

    rotateTangle !rot tangle
        | l == 0 || rot == 0  = tangle
        | otherwise           =
            tangle
                { involutionArray = PV.create $ do
                    let n = 4 * numberOfVertices tangle
                        a = involutionArray tangle
                        modify i | i < n      = i
                                 | otherwise  = n + mod (i - n + rot) l
                    a' <- PMV.new (n + l)
                    forM_ [0 .. n - 1] $ \ !i ->
                        PMV.unsafeWrite a' i $ modify (a `PV.unsafeIndex` i)
                    forM_ [0 .. l - 1] $ \ !i ->
                        PMV.unsafeWrite a' (n + mod (i + rot) l) $ modify (a `PV.unsafeIndex` (n + i))
                    return a'
                }
        where
            l = numberOfLegs tangle

    mirrorTangleWith f tangle =
        tangle
            { involutionArray = PV.create $ do
                let l = numberOfLegs tangle
                    n = 4 * numberOfVertices tangle
                    a = involutionArray tangle
                    modify i | i < n      = (i .&. complement 3) + ((-i) .&. 3)
                             | otherwise  = n + mod (n - i) l
                a' <- PMV.new (n + l)
                forM_ [0 .. n + l - 1] $ \ !i ->
                    PMV.unsafeWrite a' (modify i) $ modify (a `PV.unsafeIndex` i)
                return a'
            , crossingsArray = f `fmap` crossingsArray tangle
            }

    glueTangles legsToGlue legA legB = ST.runST $ do
        unless (isLeg legA) $
            fail $ printf "glueTangles: first leg parameter %s is not a leg" (show legA)
        unless (isLeg legB) $
            fail $ printf "glueTangles: second leg parameter %s is not a leg" (show legB)

        let tangleA = dartOwner legA
            lA = numberOfLegs tangleA
            nA = numberOfVertices tangleA
            lpA = legPlace legA

            tangleB = dartOwner legB
            lB = numberOfLegs tangleB
            nB = numberOfVertices tangleB
            lpB = legPlace legB

        when (legsToGlue < 0 || legsToGlue > min lA lB) $
            fail $ printf "glueTangles: number of legs to glue %i is out of bound" legsToGlue

        let newL = lA + lB - 2 * legsToGlue
            newC = nA + nB

        visited <- MV.replicate legsToGlue False

        cr <- do
            let {-# INLINE convertA #-}
                convertA !x
                    | x < 4 * nA        = return $! x
                    | ml >= legsToGlue  = return $! 4 * newC + ml - legsToGlue
                    | otherwise         = do
                        MV.unsafeWrite visited ml True
                        convertB (involutionArray tangleB `PV.unsafeIndex` (4 * nB + (lpB - ml) `mod` lB))
                    where
                        ml = (x - 4 * nA - lpA) `mod` lA

                {-# INLINE convertB #-}
                convertB !x
                    | x < 4 * nB            = return $! 4 * nA + x
                    | ml < lB - legsToGlue  = return $! 4 * newC + ml + lA - legsToGlue
                    | otherwise             = do
                        MV.unsafeWrite visited (lB - ml - 1) True
                        convertA (involutionArray tangleA `PV.unsafeIndex` (4 * nA + (lpA + lB - ml - 1) `mod` lA))
                    where
                        ml = (x - 4 * nB - lpB - 1) `mod` lB

            cr <- PMV.new (4 * newC + newL)
            forM_ [0 .. 4 * nA - 1] $ \ !i ->
                convertA (involutionArray tangleA `PV.unsafeIndex` i)
                    >>= PMV.unsafeWrite cr i

            forM_ [0 .. 4 * nB - 1] $ \ !i ->
                convertB (involutionArray tangleB `PV.unsafeIndex` i)
                    >>= PMV.unsafeWrite cr (4 * nA + i)

            forM_ [0 .. lA - legsToGlue - 1] $ \ !i ->
                convertA (involutionArray tangleA `PV.unsafeIndex` (4 * nA + (lpA + legsToGlue + i) `mod` lA))
                    >>= PMV.unsafeWrite cr (4 * newC + i)

            forM_ [0 .. lB - legsToGlue - 1] $ \ !i ->
                convertB (involutionArray tangleB `PV.unsafeIndex` (4 * nB + (lpB + 1 + i) `mod` lB))
                    >>= PMV.unsafeWrite cr (4 * newC + lA - legsToGlue + i)
            PV.unsafeFreeze cr

        extraLoops <- do
            let markA a = do
                    let ai = 4 * nA + (lpA + a) `mod` lA
                        bi = involutionArray tangleA `PV.unsafeIndex` ai
                        b = (bi - 4 * nA - lpA) `mod` lA
                    v <- MV.unsafeRead visited b
                    unless v $ MV.unsafeWrite visited b True >> markB b

                markB a = do
                    let ai = 4 * nB + (lpB - a) `mod` lB
                        bi = involutionArray tangleB `PV.unsafeIndex` ai
                        b = (lpB - (bi - 4 * nB)) `mod` lB
                    v <- MV.unsafeRead visited b
                    unless v $ MV.unsafeWrite visited b True >> markA b

            foldM (\ !s !i -> do
                    v <- MV.unsafeRead visited i
                    if v
                        then return $! s
                        else markA i >> (return $! s + 1)
                ) 0 [0 .. legsToGlue - 1]

        return Tangle
            { loopsCount      = numberOfFreeLoops tangleA + numberOfFreeLoops tangleB + extraLoops
            , vertexCount     = newC
            , involutionArray = cr
            , crossingsArray  = crossingsArray tangleA V.++ crossingsArray tangleB
            , legsCount       = newL
            }

    glueToBorder leg legsToGlue !crossingToGlue = ST.runST $ do
        unless (isLeg leg) $
            fail $ printf "glueToBorder: leg expected, but %s received" (show leg)

        when (legsToGlue < 0 || legsToGlue > 4) $
            fail $ printf "glueToBorder: legsToGlue must be in [0 .. 4], but %i found" legsToGlue

        let tangle = dartOwner leg
            oldL = numberOfLegs tangle
        when (oldL < legsToGlue) $
            fail $ printf "glueToBorder: not enough legs to glue (l = %i, legsToGlue = %i)" oldL legsToGlue

        let oldC = numberOfVertices tangle
            newC = oldC + 1
            newL = oldL + 4 - 2 * legsToGlue
            lp = legPlace leg

        let result = Tangle
                { loopsCount      = numberOfFreeLoops tangle
                , vertexCount     = newC
                , involutionArray = PV.create $ do
                    cr <- PMV.new (4 * newC + newL)

                    let {-# INLINE copyModified #-}
                        copyModified !index !index' =
                            let y | x < 4 * oldC            = x
                                  | ml < oldL - legsToGlue  = 4 * newC + 4 - legsToGlue + ml
                                  | otherwise               = 4 * newC - 5 + oldL - ml
                                  where
                                      x = involutionArray tangle `PV.unsafeIndex` index'
                                      ml = (x - 4 * oldC - lp - 1) `mod` oldL
                            in PMV.unsafeWrite cr index y

                    forM_ [0 .. 4 * oldC - 1] $ \ !i ->
                        copyModified i i

                    forM_ [0 .. legsToGlue - 1] $ \ !i ->
                        copyModified (4 * (newC - 1) + i) (4 * oldC + ((lp - i) `mod` oldL))

                    forM_ [0 .. 3 - legsToGlue] $ \ !i -> do
                        let a = 4 * (newC - 1) + legsToGlue + i
                            b = 4 * newC + i
                        PMV.unsafeWrite cr a b
                        PMV.unsafeWrite cr b a

                    forM_ [0 .. oldL - 1 - legsToGlue] $ \ !i ->
                        copyModified (4 * newC + i + 4 - legsToGlue) (4 * oldC + ((lp + 1 + i) `mod` oldL))

                    return $! cr

                , crossingsArray  = V.snoc (crossingsArray tangle) crossingToGlue
                , legsCount       = newL
                }

        return $! nthVertex result newC

    tensorSubst k crossF tangle = implode (k * numberOfFreeLoops tangle, border, body)
        where
            n = numberOfVertices tangle

            crossSubst =
                let substList = do
                        c <- allVertices tangle
                        let t = crossF c
                        when (numberOfLegs t /= 4 * k) $
                            fail "bad number of legs"
                        return $! t
                in V.fromListN (n + 1) $ undefined : substList

            crossOffset = UV.fromListN (n + 1) $
                0 : scanl (\ !p !i -> p + numberOfVertices (crossSubst V.! i)) 0 [1 .. n]

            resolveInCrossing !v !d
                | isLeg d    =
                    let p = legPlace d
                    in resolveOutside (opposite $ nthOutcomingDart v $ p `div` k) (p `mod` k)
                | otherwise  =
                    let (c, p) = beginPair' d
                    in ((crossOffset UV.! vertexIndex v) + c, p)

            resolveOutside !d !i
                | isLeg d    = (0, k * legPlace d + i)
                | otherwise  =
                    let (c, p) = beginPair d
                    in resolveInCrossing c $ opposite $
                            nthLeg (crossSubst V.! vertexIndex c) (k * p + k - 1 - i)

            border = do
                d <- allLegOpposites tangle
                i <- [0 .. k - 1]
                return $! resolveOutside d $ k - 1 - i

            body = do
                c <- allVertices tangle
                let t = crossSubst V.! vertexIndex c
                c' <- allVertices t
                return (map (resolveInCrossing c) $ incomingDarts c', vertexCrossing c')


instance (Show a) => Show (Tangle a) where
    show = printf "implode %s" . show . explode


instance (Show a) => Show (Vertex Tangle a) where
    show v =
        printf "(Crossing %i %s [ %s ])"
            (vertexIndex v)
            (show $ vertexCrossing v)
            (unwords $ map (show . opposite) $ outcomingDarts v)


instance Show (Dart Tangle a) where
    show d | isLeg d    = printf "(Leg %i)" $ legPlace d
           | otherwise  = let (c, p) = beginPair' d
                          in printf "(Dart %i %i)" c p


instance (Crossing a) => KnotWithPrimeTest Tangle a where
    isPrime tangle = connections == nub connections
        where
            idm = let faces = directedPathsDecomposition (nextCW, nextCCW)
                  in M.fromList $ concatMap (\ (face, i) -> zip face $ repeat i) $ zip faces [(0 :: Int) ..]

            connections =
                let getPair (da, db) =
                        let a = idm M.! da
                            b = idm M.! db
                        in (min a b, max a b)
                in sort $ map getPair $ allEdges tangle

            directedPathsDecomposition continue =
                let processDart (paths, s) d
                        | S.member d s  = (paths, s)
                        | otherwise     = (path : paths, nextS)
                        where
                            path = containingDirectedPath continue d
                            nextS = foldl' (flip S.insert) s path
                in fst $ foldl' processDart ([], S.empty) $ allHalfEdges tangle

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


type TangleProjection = Tangle ProjectionCrossing
type TangleProjectionVertex = Vertex Tangle ProjectionCrossing
type TangleProjectionDart = Dart Tangle ProjectionCrossing


type TangleDiagram = Tangle DiagramCrossing
type TangleDiagramVertex = Vertex Tangle DiagramCrossing
type TangleDiagramDart = Dart Tangle DiagramCrossing



data CrossingFlag a = Direct !a | Flipped !a | Masked

data MoveState s a =
    MoveState
        { stateSource      :: !(Tangle a)
        , stateMask        :: !(MV.STVector s (CrossingFlag a))
        , stateCircles     :: !(STRef.STRef s Int)
        , stateConnections :: !(MV.STVector s (Dart Tangle a))
        }


{-# INLINE withState #-}
withState :: (MoveState s a -> ST.ST s x) -> ModifyM Tangle a s x
withState f = ModifyTangleM $ do
    st <- Reader.ask
    Reader.lift (f st)


instance ModifyDSL Tangle where
    newtype ModifyM Tangle a s x = ModifyTangleM { unM :: Reader.ReaderT (MoveState s a) (ST.ST s) x }
        deriving (Functor, Applicative, Monad)

    modifyKnot initial modification = ST.runST $ do
        st <- disassembleST initial
        Reader.runReaderT (unM modification) st
        assembleST st

    aliveCrossings = do
        tangle <- withState (return . stateSource)
        filterM (fmap not . isMaskedC) $ allVertices tangle

    emitLoopsC dn =
        withState $ \ !st ->
            STRef.modifySTRef' (stateCircles st) (+ dn)

    oppositeC d = do
        when (isDart d) $ do
            masked <- isMaskedC $ beginVertex d
            when masked $
                fail $ printf "oppositeC: touching masked crossing when taking from %s" (show d)
        withState $ \ s ->
            MV.read (stateConnections s) (dartIndex d)

    passOverC d =
        withState $ \ !st -> do
            when (isLeg d) $ fail $ printf "passOverC: leg %s passed" (show d)
            msk <- readMaskST st $ beginVertex d
            case msk of
                Masked    -> fail "passOverC: touching masked crossing when taking from %s" (show d)
                Direct t  -> return $! passOver' t (beginPlace d)
                Flipped t -> return $! passOver' t (3 - beginPlace d)

    maskC crossings =
        withState $ \ !st ->
            forM_ crossings $ \ !c ->
                writeMaskST st c Masked

    isMaskedC c =
        withState $ \ !st -> do
            msk <- readMaskST st c
            return $! case msk of
                Masked -> True
                _      -> False

    modifyC needFlip f crossings =
        withState $ \ !st ->
            forM_ crossings $ \ !c -> do
                msk <- readMaskST st c
                writeMaskST st c $
                    case msk of
                        Direct s  | needFlip  -> Flipped $ f s
                                  | otherwise -> Direct $ f s
                        Flipped s | needFlip  -> Direct $ f s
                                  | otherwise -> Flipped $ f s
                        Masked                -> error $ printf "modifyC: flipping masked crossing %s" (show c)

    connectC connections =
        withState $ \ !st ->
            reconnectST st connections

    substituteC substitutions = do
        reconnections <- mapM (\ (a, b) -> (,) a `fmap` oppositeC b) substitutions
        withState $ \ !st -> do
            let source = stateSource st

            arr <- MV.new (numberOfDarts source)
            forM_ (allEdges source) $ \ (!a, !b) -> do
                MV.write arr (dartIndex a) a
                MV.write arr (dartIndex b) b

            forM_ substitutions $ \ (a, b) ->
                if a == b
                    then STRef.modifySTRef' (stateCircles st) (+ 1)
                    else MV.write arr (dartIndex b) a

            (reconnectST st =<<) $ forM reconnections $ \ (a, b) ->
                (,) a `fmap` MV.read arr (dartIndex b)


readMaskST :: MoveState s a -> Vertex Tangle a -> ST.ST s (CrossingFlag a)
readMaskST st c = MV.read (stateMask st) (vertexIndex c)


writeMaskST :: MoveState s a -> Vertex Tangle a -> CrossingFlag a -> ST.ST s ()
writeMaskST st c = MV.write (stateMask st) (vertexIndex c)


reconnectST :: MoveState s a -> [(Dart Tangle a, Dart Tangle a)] -> ST.ST s ()
reconnectST st connections =
    forM_ connections $ \ (!a, !b) -> do
        when (a == b) $ fail $ printf "reconnect: %s connect to itself" (show a)
        MV.write (stateConnections st) (dartIndex a) b
        MV.write (stateConnections st) (dartIndex b) a


disassembleST :: Tangle a -> ST.ST s (MoveState s a)
disassembleST tangle = do
    connections <- MV.new (numberOfDarts tangle)
    forM_ (allEdges tangle) $ \ (!a, !b) -> do
        MV.write connections (dartIndex a) b
        MV.write connections (dartIndex b) a

    mask <- MV.new (numberOfVertices tangle + 1)
    forM_ (allVertices tangle) $ \ v ->
        MV.write mask (vertexIndex v) (Direct $ vertexCrossing v)

    circlesCounter <- STRef.newSTRef $ numberOfFreeLoops tangle
    return MoveState
        { stateSource      = tangle
        , stateMask        = mask
        , stateCircles     = circlesCounter
        , stateConnections = connections
        }


assembleST :: (Show a) => MoveState s a -> ST.ST s (Tangle a)
assembleST st = do
    let source = stateSource st

    offset <- UMV.new (numberOfVertices source + 1)
    foldM_ (\ !x !c -> do
            msk <- readMaskST st c
            case msk of
                Masked -> return x
                _      -> UMV.write offset (vertexIndex c) x >> (return $! x + 1)
        ) 1 (allVertices source)

    let pair d | isLeg d    = return $! (,) 0 $! legPlace d
               | otherwise  = do
                   let i = beginVertexIndex d
                   msk <- MV.read (stateMask st) i
                   off <- UMV.read offset i
                   case msk of
                       Direct _  -> return (off, beginPlace d)
                       Flipped _ -> return (off, 3 - beginPlace d)
                       Masked    -> fail $ printf "assemble: %s is touching masked crossing %i at:\n%s" (show d) i (show $ stateSource st)

    let opp d = MV.read (stateConnections st) (dartIndex d)

    border <- forM (allLegs source) (opp >=> pair)
    connections <- do
        alive <- flip filterM (allVertices source) $ \ !c -> do
            msk <- readMaskST st c
            return $! case msk of
                Masked -> False
                _      -> True

        forM alive $ \ !c -> do
                msk <- readMaskST st c
                con <- mapM (opp >=> pair) $ outcomingDarts c
                return $! case msk of
                    Direct s  -> (con, s)
                    Flipped s -> (reverse con, s)
                    Masked    -> error "assemble: internal error"

    circles <- STRef.readSTRef (stateCircles st)
    return $! implode (circles, border, connections)




data ProjectionPattern = W | X | M
    deriving (Eq, Enum, Show, Read)


data DiagramPattern = WO | WU | XO | XU | MO | MU
    deriving (Eq, Enum)


instance Show DiagramPattern where
    show p = case p of
        WO -> "W+"
        WU -> "W-"
        XO -> "X+"
        XU -> "X-"
        MO -> "M+"
        MU -> "M-"


instance Read DiagramPattern where
    readsPrec _ s = case dropWhile isSpace s of
        'W' : '+' : t -> [(WO, t)]
        'W' : '-' : t -> [(WU, t)]
        'X' : '+' : t -> [(XO, t)]
        'X' : '-' : t -> [(XU, t)]
        'M' : '+' : t -> [(MO, t)]
        'M' : '-' : t -> [(MU, t)]
        _             -> []


class (Enum (CascadePattern a)) => CascadeCodePattern a where
    type CascadePattern a :: *
    cascadeCodeRoot :: Tangle a
    decodeCrossing  :: CascadePattern a -> (ProjectionPattern, Int, Int, a)


decodeCascadeCode :: (CascadeCodePattern a) => [(CascadePattern a, Int)] -> Tangle a
decodeCascadeCode =
    foldl (\ prev (pattern, offset) ->
            let (gl, shift, rot, c) = decodeCrossing pattern
                p | rot == 0   = id
                  | otherwise  = rotateTangle rot
            in p $ vertexOwner $ glueToBorder
                (nthLeg prev $ offset + shift)
                (case gl of { W -> 3 ; X -> 2 ; M -> 1 })
                c
        ) cascadeCodeRoot


instance CascadeCodePattern ProjectionCrossing where
    type CascadePattern ProjectionCrossing = ProjectionPattern

    cascadeCodeRoot = lonerTangle projectionCrossing

    decodeCrossing W = (W, 1, 0, projectionCrossing)
    decodeCrossing X = (X, 1, 0, projectionCrossing)
    decodeCrossing M = (M, 0, -1, projectionCrossing)


instance CascadeCodePattern DiagramCrossing where
    type CascadePattern DiagramCrossing = DiagramPattern

    cascadeCodeRoot = lonerTangle overCrossing

    decodeCrossing WO = (W, 1, 0, underCrossing)
    decodeCrossing WU = (W, 1, 0, overCrossing)
    decodeCrossing XO = (X, 1, 0, overCrossing)
    decodeCrossing XU = (X, 1, 0, underCrossing)
    decodeCrossing MO = (M, 0, -1, overCrossing)
    decodeCrossing MU = (M, 0, -1, underCrossing)


decodeCascadeCodeFromPairs :: [(Int, Int)] -> TangleProjection
decodeCascadeCodeFromPairs = (decodeCascadeCode .) $ map $ \ (p, off) ->
    flip (,) off $ case p of
        -1 -> W
        0  -> X
        1  -> M
        _  -> error $ printf "decodeCascadeCodeFromPairs: expected -1, 0 or 1 as pattern, %i received" p
