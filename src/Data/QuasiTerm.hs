module Data.QuasiTerm where

import Numeric.Half

import Data.Basic

data QuasiTerm
  = QuasiTermTau
  | QuasiTermUpsilon Identifier
  | QuasiTermPi [IdentifierPlus] QuasiTermPlus
  | QuasiTermPiIntro [IdentifierPlus] QuasiTermPlus
  | QuasiTermPiElim QuasiTermPlus [QuasiTermPlus]
  | QuasiTermMu IdentifierPlus QuasiTermPlus
  | QuasiTermZeta Identifier
  | QuasiTermConst Identifier
  | QuasiTermConstDecl IdentifierPlus QuasiTermPlus
  | QuasiTermIntS IntSize Integer
  | QuasiTermIntU IntSize Integer
  | QuasiTermInt Integer
  | QuasiTermFloat16 Half
  | QuasiTermFloat32 Float
  | QuasiTermFloat64 Double
  | QuasiTermFloat Double
  | QuasiTermEnum EnumType
  | QuasiTermEnumIntro EnumValue
  | QuasiTermEnumElim QuasiTermPlus [(Case, QuasiTermPlus)]
  | QuasiTermArray
      ArrayKind -- type of elements
      QuasiTermPlus -- type of index
  | QuasiTermArrayIntro ArrayKind [(EnumValue, QuasiTermPlus)]
  | QuasiTermArrayElim ArrayKind QuasiTermPlus QuasiTermPlus
  deriving (Show)

type QuasiTermPlus = (WeakMeta, QuasiTerm)

type SubstQuasiTerm = [(Identifier, QuasiTermPlus)]

type Hole = Identifier

type IdentifierPlus = (Identifier, QuasiTermPlus)

data WeakMeta
  = WeakMetaTerminal (Maybe Loc)
  | WeakMetaNonTerminal (Maybe Loc)
  deriving (Show) -- data WeakMeta