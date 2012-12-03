module Math.KnotTh.Tangles.BorderIncremental.SimpleTypes
	( module Math.KnotTh.Tangles.BorderIncremental.IncrementalGluing
	, primeProjectionType
	, reducedProjectionType
	, templateProjectionType
	, primeDiagramType
	, primeIrreducibleDiagramType
	, triangleBoundedType
	) where

import Math.Algebra.Group.Dn (DnSubGroup)
import Math.KnotTh.Tangles.Projection
import Math.KnotTh.Tangles.NonAlternating
import Math.KnotTh.Tangles.BorderIncremental.IncrementalGluing
import Math.KnotTh.Tangles.BorderIncremental.IncrementalTests


primeProjectionType :: GluingType ProjectionCrossing DnSubGroup
primeProjectionType = GluingType
	{ preGlueTest  = \ _ _ _ -> True
	, postGlueTest = \ _ _ _ s -> return $! s
	}


reducedProjectionType :: GluingType ProjectionCrossing DnSubGroup
reducedProjectionType = GluingType
	{ preGlueTest  = const testNoMultiEdges
	, postGlueTest = \ _ _ _ s -> return $! s
	}


templateProjectionType :: GluingType ProjectionCrossing DnSubGroup
templateProjectionType = GluingType
	{ preGlueTest  = \ _ leg gl ->
		let	t = dartTangle leg
			n = numberOfCrossings t
			l = numberOfLegs t
		in (n == 1 || l > 4) && testNoMultiEdges leg gl
	, postGlueTest = \ root gl _ s ->
		if gl < 3 || testFlow4 root
			then return $! s
			else Nothing
	}


primeDiagramType :: GluingType ArbitraryCrossing DnSubGroup
primeDiagramType = GluingType
	{ preGlueTest  = \ _ _ _ -> True
	, postGlueTest = \ _ _ _ s -> return $! s
	}


primeIrreducibleDiagramType :: GluingType ArbitraryCrossing DnSubGroup
primeIrreducibleDiagramType = GluingType
	{ preGlueTest  = testNo2ndReidemeisterReduction
	, postGlueTest = \ _ _ _ s -> return $! s
	}


triangleBoundedType :: Int -> GluingType ct a -> GluingType ct a
triangleBoundedType maxN gt = gt
	{ preGlueTest = \ cr leg gl ->
		let t = dartTangle leg
		in (diagonalIndex (1 + numberOfCrossings t) (nextNumberOfLegs (numberOfLegs t) gl) <= diagonalIndex maxN 4)
			&& preGlueTest gt cr leg gl
	}
