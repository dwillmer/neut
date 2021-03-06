module Data.Term where

import Data.EnumCase
import Data.Ident
import qualified Data.IntMap as IntMap
import Data.LowType
import Data.Maybe (fromMaybe)
import Data.Meta
import qualified Data.Set as S
import Data.Size
import qualified Data.Text as T
import Data.WeakTerm

data Term
  = TermTau
  | TermUpsilon Ident
  | TermPi [IdentPlus] TermPlus
  | TermPiIntro [IdentPlus] TermPlus
  | TermPiElim TermPlus [TermPlus]
  | TermFix IdentPlus [IdentPlus] TermPlus
  | TermConst T.Text
  | TermInt IntSize Integer
  | TermFloat FloatSize Double
  | TermEnum T.Text
  | TermEnumIntro T.Text
  | TermEnumElim (TermPlus, TermPlus) [(EnumCasePlus, TermPlus)]
  | TermArray TermPlus ArrayKind -- array (LENGTH-in-i64) (KIND)
  | TermArrayIntro ArrayKind [TermPlus]
  | TermArrayElim ArrayKind [IdentPlus] TermPlus TermPlus
  | TermStruct [ArrayKind]
  | TermStructIntro [(TermPlus, ArrayKind)]
  | TermStructElim [(Meta, Ident, ArrayKind)] TermPlus TermPlus
  deriving (Show)

type TermPlus =
  (Meta, Term)

type SubstTerm =
  IntMap.IntMap TermPlus

type IdentPlus =
  (Meta, Ident, TermPlus)

asUpsilon :: TermPlus -> Maybe Ident
asUpsilon term =
  case term of
    (_, TermUpsilon x) ->
      Just x
    _ ->
      Nothing

varTermPlus :: TermPlus -> S.Set Int
varTermPlus term =
  case term of
    (_, TermTau) ->
      S.empty
    (_, TermUpsilon x) ->
      S.singleton (asInt x)
    (_, TermPi xts t) ->
      varTermPlus' xts [t]
    (_, TermPiIntro xts e) ->
      varTermPlus' xts [e]
    (_, TermPiElim e es) -> do
      let xs1 = varTermPlus e
      let xs2 = S.unions $ map varTermPlus es
      S.union xs1 xs2
    (_, TermFix (_, x, t) xts e) -> do
      let set1 = varTermPlus t
      let set2 = S.filter (/= asInt x) (varTermPlus' xts [e])
      S.union set1 set2
    (_, TermConst _) ->
      S.empty
    (_, TermInt _ _) ->
      S.empty
    (_, TermFloat _ _) ->
      S.empty
    (_, TermEnum _) ->
      S.empty
    (_, TermEnumIntro _) ->
      S.empty
    (_, TermEnumElim (e, t) les) -> do
      let xs = varTermPlus t
      let ys = varTermPlus e
      let zs = S.unions $ map (varTermPlus . snd) les
      S.unions [xs, ys, zs]
    (_, TermArray dom _) ->
      varTermPlus dom
    (_, TermArrayIntro _ es) ->
      S.unions $ map varTermPlus es
    (_, TermArrayElim _ xts d e) ->
      varTermPlus d `S.union` varTermPlus' xts [e]
    (_, TermStruct {}) ->
      S.empty
    (_, TermStructIntro ets) ->
      S.unions $ map (varTermPlus . fst) ets
    (_, TermStructElim xts d e) -> do
      let xs = map (\(_, x, _) -> asInt x) xts
      let set1 = varTermPlus d
      let set2 = S.filter (`notElem` xs) (varTermPlus e)
      S.union set1 set2

varTermPlus' :: [IdentPlus] -> [TermPlus] -> S.Set Int
varTermPlus' binder es =
  case binder of
    [] ->
      S.unions $ map varTermPlus es
    ((_, x, t) : xts) -> do
      let set1 = varTermPlus t
      let set2 = varTermPlus' xts es
      S.union set1 $ S.filter (/= asInt x) set2

substTermPlus :: SubstTerm -> TermPlus -> TermPlus
substTermPlus sub term =
  case term of
    (m, TermTau) ->
      (m, TermTau)
    (m, TermUpsilon x) ->
      fromMaybe (m, TermUpsilon x) (IntMap.lookup (asInt x) sub)
    (m, TermPi xts t) -> do
      let (xts', t') = substTermPlus'' sub xts t
      (m, TermPi xts' t')
    (m, TermPiIntro xts body) -> do
      let (xts', body') = substTermPlus'' sub xts body
      (m, TermPiIntro xts' body')
    (m, TermPiElim e es) -> do
      let e' = substTermPlus sub e
      let es' = map (substTermPlus sub) es
      (m, TermPiElim e' es')
    (m, TermFix (mx, x, t) xts e) -> do
      let t' = substTermPlus sub t
      let sub' = IntMap.delete (asInt x) sub
      let (xts', e') = substTermPlus'' sub' xts e
      (m, TermFix (mx, x, t') xts' e')
    (_, TermConst _) ->
      term
    (_, TermInt _ _) ->
      term
    (_, TermFloat _ _) ->
      term
    (m, TermEnum x) ->
      (m, TermEnum x)
    (m, TermEnumIntro l) ->
      (m, TermEnumIntro l)
    (m, TermEnumElim (e, t) branchList) -> do
      let t' = substTermPlus sub t
      let e' = substTermPlus sub e
      let (caseList, es) = unzip branchList
      let es' = map (substTermPlus sub) es
      (m, TermEnumElim (e', t') (zip caseList es'))
    (m, TermArray dom k) -> do
      let dom' = substTermPlus sub dom
      (m, TermArray dom' k)
    (m, TermArrayIntro k es) -> do
      let es' = map (substTermPlus sub) es
      (m, TermArrayIntro k es')
    (m, TermArrayElim mk xts v e) -> do
      let v' = substTermPlus sub v
      let (xts', e') = substTermPlus'' sub xts e
      (m, TermArrayElim mk xts' v' e')
    (m, TermStruct ts) ->
      (m, TermStruct ts)
    (m, TermStructIntro ets) -> do
      let (es, ts) = unzip ets
      let es' = map (substTermPlus sub) es
      (m, TermStructIntro $ zip es' ts)
    (m, TermStructElim xts v e) -> do
      let v' = substTermPlus sub v
      let xs = map (\(_, x, _) -> asInt x) xts
      let sub' = foldr IntMap.delete sub xs
      let e' = substTermPlus sub' e
      (m, TermStructElim xts v' e')

substTermPlus' :: SubstTerm -> [IdentPlus] -> [IdentPlus]
substTermPlus' sub binder =
  case binder of
    [] ->
      []
    (m, x, t) : xts -> do
      let sub' = IntMap.delete (asInt x) sub
      let xts' = substTermPlus' sub' xts
      let t' = substTermPlus sub t
      (m, x, t') : xts'

substTermPlus'' :: SubstTerm -> [IdentPlus] -> TermPlus -> ([IdentPlus], TermPlus)
substTermPlus'' sub binder e =
  case binder of
    [] ->
      ([], substTermPlus sub e)
    (mx, x, t) : xts -> do
      let sub' = IntMap.delete (asInt x) sub
      let (xts', e') = substTermPlus'' sub' xts e
      ((mx, x, substTermPlus sub t) : xts', e')

weaken :: TermPlus -> WeakTermPlus
weaken term =
  case term of
    (m, TermTau) ->
      (m, WeakTermTau)
    (m, TermUpsilon x) ->
      (m, WeakTermUpsilon x)
    (m, TermPi xts t) ->
      (m, WeakTermPi (weakenArgs xts) (weaken t))
    (m, TermPiIntro xts body) -> do
      let xts' = weakenArgs xts
      (m, WeakTermPiIntro xts' (weaken body))
    (m, TermPiElim e es) -> do
      let e' = weaken e
      let es' = map weaken es
      (m, WeakTermPiElim e' es')
    (m, TermFix (mx, x, t) xts e) -> do
      let t' = weaken t
      let xts' = weakenArgs xts
      let e' = weaken e
      (m, WeakTermFix (mx, x, t') xts' e')
    (m, TermConst x) ->
      (m, WeakTermConst x)
    (m, TermInt size x) ->
      (m, WeakTermInt (m, WeakTermConst (showIntSize size)) x)
    (m, TermFloat size x) ->
      (m, WeakTermFloat (m, WeakTermConst (showFloatSize size)) x)
    (m, TermEnum x) ->
      (m, WeakTermEnum x)
    (m, TermEnumIntro l) ->
      (m, WeakTermEnumIntro l)
    (m, TermEnumElim (e, t) branchList) -> do
      let t' = weaken t
      let e' = weaken e
      let (caseList, es) = unzip branchList
      let es' = map weaken es
      (m, WeakTermEnumElim (e', t') (zip caseList es'))
    (m, TermArray dom k) -> do
      let dom' = weaken dom
      (m, WeakTermArray dom' k)
    (m, TermArrayIntro k es) -> do
      let es' = map weaken es
      (m, WeakTermArrayIntro k es')
    (m, TermArrayElim mk xts v e) -> do
      let v' = weaken v
      let xts' = weakenArgs xts
      let e' = weaken e
      (m, WeakTermArrayElim mk xts' v' e')
    (m, TermStruct ts) ->
      (m, WeakTermStruct ts)
    (m, TermStructIntro ets) -> do
      let (es, ts) = unzip ets
      let es' = map weaken es
      (m, WeakTermStructIntro $ zip es' ts)
    (m, TermStructElim xts v e) -> do
      let v' = weaken v
      let e' = weaken e
      (m, WeakTermStructElim xts v' e')

weakenArgs :: [(Meta, Ident, TermPlus)] -> [(Meta, Ident, WeakTermPlus)]
weakenArgs xts = do
  let (ms, xs, ts) = unzip3 xts
  zip3 ms xs (map weaken ts)
