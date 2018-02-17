module RuleParser 
( parseRules
, apply
, _typeDef
, _field
, _path
, _pathParts
, _pathVar
, _pathWild
, _pathStatic
, _pathDir
, _funcMember
, FuncDef (..)
, TypeDef (..)
, PathDef (..)
, PathPart (..)
, PathDirective (..)
, PathBodyItem (..)
, TypeRef (..)
, TopLevel (..)
, Member (..)
) where

import Parser
import Control.Applicative (optional)
import Data.Char (isSpace)

data FuncDef = FuncDef [String] String deriving (Show, Eq)

data TypeDef = TypeDef [Member] deriving (Show, Eq)

type PathOp = String
type PathCondition = String
data PathDirective = PathDirective [PathOp] PathCondition
  deriving (Show, Eq)
data PathDef = PathDef [PathPart] (Maybe String) [PathBodyItem]
  deriving (Show, Eq)
data PathPart = PathPartStatic String 
              | PathPartVar String 
              | PathPartWild String
  deriving (Show, Eq)

data PathBodyItem = PathBodyDir PathDirective
                  | PathBodyPath PathDef
                  | PathBodyFunc FuncDef
  deriving (Show, Eq)

-- data Object = Type TypeDef | Path PathDef | Func FuncDef
data TypeRef = TypeNameRef String | InlineTypeRef TypeDef deriving (Show, Eq)
data Member = MemberFunc String FuncDef | MemberField String [TypeRef] deriving (Show, Eq)

_alpha = lower <|> upper
_alphaNum = _alpha <|> digit
_varStart = _alpha <|> oneOf "_$"
_varName = do
  c <- _varStart
  rest <- many (_alphaNum <|> oneOf "_$")
  return (c:rest)

separated = manywith . symbol

_funcBody :: Parser String
_funcBody = many $ sat (/='}')


_funcMember :: Parser Member
_funcMember = do
  name <- token _varName
  params <- grouped "(" ")" paramList
  -- symbol "=>"
  body <- grouped "{" "}" _funcBody
  return $ f name params body
  where
    f n p = MemberFunc n . FuncDef p
    paramList = separated "," (token _varName)

_typeDef :: Parser TypeDef
_typeDef = grouped "{" "}" $ do
  members <- many (_field <|> _funcMember)
  return $ TypeDef members
  
_typeRefs :: Parser [TypeRef]
_typeRefs = manywith (symbol "|") ((TypeNameRef <$> token _varName) <|> (InlineTypeRef <$> _typeDef))

_field :: Parser Member
_field = do
  name <- token _varName
  symbol ":"
  types <- _typeRefs
  return $ MemberField name types

_topLevelType :: Parser TopLevel
_topLevelType = do 
  symbol "type"
  name <- token _varName
  symbol "="
  members <- _typeRefs
  return $ TopLevelType name members

_pathStatic :: Parser PathPart
_pathStatic = do
  n <- _varName
  return $ PathPartStatic n

_pathVar :: Parser PathPart
_pathVar = do
  n <- grouped "{" "}" _varName 
  return $ PathPartVar n

_pathWild :: Parser PathPart
_pathWild = grouped "{" "}" $ do
  v <- _varName
  string "=**"
  return $ PathPartWild v

_pathParts :: Parser [PathPart]
_pathParts = manywith (char '/') (_pathVar <|> _pathStatic <|> _pathWild)

_pathType :: Parser (Maybe String)
_pathType = optional $ do
  symbol "is" 
  token _varName

_pathDir :: Parser PathDirective
_pathDir = do
  symbol "allow"
  -- ops <-  _const "read"
  ops <- manywith (symbol ",") $ enum 
    [ "read"
    , "write"
    , "create"
    , "update"
    , "delete" ]
  symbol ":"
  symbol "if"
  space
  body <- many $ sat (/=';') 
  char ';'
  return $ PathDirective ops body

_path :: Parser PathDef
_path = do
  symbol "match"
  optional $ symbol "/"
  parts <- token _pathParts
  className <- _pathType
  symbol "{"
  body <- many (PathBodyPath <$> _path <|> PathBodyDir <$> _pathDir)
  symbol "}"
  return  $ PathDef parts className body

data TopLevel = TopLevelType String [TypeRef]
              | TopLevelPath PathDef
  deriving (Show, Eq)
  
_topLevel = (TopLevelPath <$> _path) <|> _topLevelType 


parseRules :: String -> [([TopLevel], String)]
parseRules = apply (many _topLevel) . trim