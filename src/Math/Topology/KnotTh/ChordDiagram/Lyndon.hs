module Math.Topology.KnotTh.ChordDiagram.Lyndon
    ( minimumCyclicShift
    ) where

import qualified Data.Vector as V


minimumCyclicShift :: (Ord a) => [a] -> (Int, [a])
minimumCyclicShift list = shift `seq` (shift, drop shift list ++ take shift list)
    where
        n = length list

        a = V.fromListN n list

        get i = a V.! mod i n

        grow i j !lyn | i + j >= 2 * n || cp == LT  = let ni = i + j - mod j lyn
                                                      in if ni < n then grow ni 1 1 else i
                      | cp == EQ                    = grow i (j + 1) lyn
                      | otherwise                   = grow i (j + 1) (j + 1)
            where cp = compare (get $ i + j) (get $ i + j - lyn)

        shift = grow 0 1 1
