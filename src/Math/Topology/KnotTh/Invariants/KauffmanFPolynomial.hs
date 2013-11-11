{-# LANGUAGE TypeFamilies #-}
module Math.Topology.KnotTh.Invariants.KauffmanFPolynomial
    ( kauffmanFPolynomial
    , normalizedKauffmanFPolynomialOfLink
    , minimalKauffmanFPolynomialOfLink
    , minimalKauffmanFPolynomialOfTangle
    ) where

import Math.Topology.KnotTh.Crossings.Arbitrary
import Math.Topology.KnotTh.Knotted
import qualified Math.Topology.KnotTh.Link as L
import qualified Math.Topology.KnotTh.Tangle as T
import Math.Topology.KnotTh.Invariants.Skein
import Math.Topology.KnotTh.Invariants.Util.Poly
import Math.Topology.KnotTh.Invariants.Util.BruteForceMinimization


a, a', z, z' :: Poly2
a  = monomial 1 "a" 1
a' = monomial 1 "a" (-1)
z  = monomial 1 "z" 1
z' = monomial 1 "z" (-1)


invertF :: Poly2 -> Poly
invertF = invert2 "a"


writheFactor :: (SkeinStructure k) => k ArbitraryCrossing -> Poly2
writheFactor knot =
    let w = selfWrithe knot
    in (if w <= 0 then a else a') ^ abs w


data KauffmanFRelation = KauffmanFRelation


instance SkeinRelation KauffmanFRelation Poly2 where
    type SkeinRelationModel KauffmanFRelation = ChordDiagramsSum

    circleFactor _ = (a + a') * z' - 1

    initialLplus _ = [(Lplus, 1)]

    twistPFactor _ = a
    twistNFactor _ = a'

    smoothLplusFactor _ = -1
    smoothLzeroFactor _ = z
    smoothLinftyFactor _ = z

    finalNormalization _ knot = (writheFactor knot *)


kauffmanFPolynomial :: (SkeinStructure k) => k ArbitraryCrossing -> ResultOnStructure k ChordDiagramsSum Poly2
kauffmanFPolynomial = evaluateSkeinRelation KauffmanFRelation


normalizedKauffmanFPolynomialOfLink :: L.NALink -> Poly2
normalizedKauffmanFPolynomialOfLink link
    | (numberOfFreeLoops link == 0) && (numberOfCrossings link == 0)  = error "kauffmanFPolynomialOfLink: emptry link provided"
    | otherwise                                                       = normalizeBy2 (a * a + 1 - a * z) (a * z * kauffmanFPolynomial link)


minimalKauffmanFPolynomialOfLink :: L.NALink -> Poly2
minimalKauffmanFPolynomialOfLink link =
    let p = kauffmanFPolynomial link
    in min p (invertF p)


minimalKauffmanFPolynomialOfTangle :: T.NATangle -> ChordDiagramsSum Poly2
minimalKauffmanFPolynomialOfTangle = bruteForceMinimumOfTangle kauffmanFPolynomial {-tangle
    | l == 0     =
        let p = kauffmanFPolynomial tangle
        in min p $ fmap invertF p
    | otherwise  = minimum $ do
        let wf = writheFactor tangle
            wf' = invertF wf
            p = fmap (* wf') $ kauffmanFPolynomial tangle
        rot <- [0 .. l - 1]
        let rotated = fmap (* wf) $ rotateChordDiagramsSum KauffmanFRelation rot p
            mirrored = mirrorChordDiagramsSum KauffmanFRelation $ fmap invertF rotated
            r = kauffmanFPolynomial $ T.rotateTangle rot $ invertCrossings tangle
            s = kauffmanFPolynomial $ T.mirrorTangle $ T.rotateTangle rot $ invertCrossings tangle
        [rotated, mirrored, r, s]
    where
        l = T.numberOfLegs tangle
-}