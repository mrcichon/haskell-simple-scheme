module Main where
import Text.ParserCombinators.Parsec hiding (spaces) 
import System.Environment
import Control.Monad


instance Show LispVal where show = showVal

symbol :: Parser Char
symbol = oneOf "!$%&|*+-:/<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space


readExpr :: String -> LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> String $ "No match: " ++ show err
    Right val ->  val
                 

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool

escapedChars :: Parser Char
escapedChars = do char '\\'
                  x <- oneOf "\\\"nrt "
                  return $ case x of 
                   '\\' -> x
                   '"' -> x
                   'n' -> '\n'
                   'r' -> '\r'
                   't' -> '\t'


parseString :: Parser LispVal
parseString = do
                char '"'
                x <- many $ escapedChars <|>  noneOf "\"\\"
                char '"'
                return $ String x


parseBool :: Parser LispVal
parseBool = do 
            char '#'
            (char 't' >> return (Bool True)) <|> (char 'f' >> return (Bool False))

parseAtom :: Parser LispVal
parseAtom = do 
              first <- letter <|> symbol
              rest <- many (letter <|> digit <|> symbol)
              let atom = first:rest
              return $ case atom of
                            "#t" -> Bool True
                            "#f" -> Bool False
                            _    -> Atom atom

parseNumber :: Parser LispVal
parseNumber = many1 digit >>= return . Number . read
                

parseList :: Parser LispVal
parseList = sepBy parseExpr spaces >>= return . List 

parseDottedList :: Parser LispVal
parseDottedList = do
                   head <- endBy parseExpr spaces
                   tail <- char '.' >> spaces >> parseExpr
                   return $ DottedList head tail

parseQuoted :: Parser LispVal
parseQuoted = do
               char '\''
               x <- parseExpr
               return $ List [Atom "quote", x]

                
parseExpr :: Parser LispVal
parseExpr = parseAtom
          <|> parseString
          <|> parseNumber
          <|> parseBool
          <|> parseQuoted 
          <|> do char '('
                 x <- try parseList <|> parseDottedList
                 char ')'
                 return x

showVal :: LispVal -> String
showVal (String contents) = "\"" ++ contents ++  "\""
showVal (Atom name) = name
showVal (Number contents) = show contents
showVal (Bool True) = "True"
showVal (Bool False) = "False"
showVal (List contents) = "(" ++ unwordsList contents ++  ")"
showVal (DottedList head tail) = "(" ++ unwordsList head ++ " . " ++ showVal tail  ++ ")"

unwordsList :: [LispVal] -> String
unwordsList = unwords . map showVal

eval :: LispVal -> LispVal
eval val@(String _) = val
eval val@(Number _) = val
eval val@(Bool _) = val
eval (List [Atom "quote", val]) = val

eval (List (Atom func : args)) = apply func $ map eval args

apply :: String -> [LispVal] -> LispVal
apply func args = maybe (Bool False) ($ args) $ lookup func primitives

primitives :: [(String, [LispVal] -> LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem)]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> LispVal
numericBinop op params = Number $ foldl1 op $ map unpackNum params

unpackNum :: LispVal -> Integer
unpackNum (Number n) = n
unpackNum (String n) = let parsed = reads n :: [(Integer, String)] in
                           if null parsed
                              then 0
                              else fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum _ = 0



 
main :: IO ()
main = getArgs >>= print . eval. readExpr .head