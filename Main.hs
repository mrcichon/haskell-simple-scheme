module Main where
import Text.ParserCombinators.Parsec hiding (spaces) 
import System.Environment
import Control.Monad
import Control.Monad.Except


instance Show LispVal where show = showVal

symbol :: Parser Char
symbol = oneOf "!$%&|*+-:/<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space


readExpr :: String -> ThrowsError LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> throwError $ Parser err
    Right val ->  return val
                 

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool


data LispError = NumArgs Integer [LispVal]
                | TypeMismatch String LispVal
                | Parser ParseError
                | BadSpecialForm String LispVal
                | NotFunction String String
                | UnboundVar String String
                | Default String

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

eval :: LispVal -> ThrowsError LispVal
eval val@(String _) = return val
eval val@(Number _) = return val
eval val@(Bool _) = return val
eval (List [Atom "quote", val]) = return val
eval (List (Atom func : args)) = mapM eval args >>= apply func
eval badForm = throwError $ BadSpecialForm "Unrecognized special form" badForm


apply :: String -> [LispVal] -> ThrowsError LispVal
apply func args = maybe (throwError $ NotFunction "Unrecognized primitive function args" func)
			($ args)
			(lookup func primitives)

primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem),
	      ("=", numBoolBinop (==)),
              ("<", numBoolBinop (<)),
              (">", numBoolBinop (>)),
              ("/=", numBoolBinop (/=)),
              (">=", numBoolBinop (>=)),
              ("<=", numBoolBinop (<=)),
              ("&&", boolBoolBinop (&&)),
              ("||", boolBoolBinop (||))]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> ThrowsError LispVal
numericBinop op           []  = throwError $ NumArgs 2 []
numericBinop op singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op params        = mapM unpackNum params >>= return . Number . foldl1 op

boolBinop :: (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinop unpacker op args = if length args /= 2 
                             then throwError $ NumArgs 2 args
                             else do left <- unpacker $ args !! 0
                                     right <- unpacker $ args !! 1
                                     return $ Bool $ left `op` right

numBoolBinop  = boolBinop unpackNum
strBoolBinop  = boolBinop unpackStr
boolBoolBinop = boolBinop unpackBool


unpackStr :: LispVal -> ThrowsError String
unpackStr (String s) = return s
unpackStr (Number s) = return $ show s
unpackStr (Bool s)   = return $ show s
unpackStr notString  = throwError $ TypeMismatch "string" notString

unpackBool :: LispVal -> ThrowsError Bool
unpackBool (Bool b) = return b
unpackBool notBool  = throwError $ TypeMismatch "boolean" notBool



unpackNum :: LispVal -> ThrowsError Integer
unpackNum (Number n) = return n
unpackNum (String n) = let parsed = reads n in
                           if null parsed
                              then throwError $ TypeMismatch "number" $ String n
			      else return $ fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum notNum     = throwError $ TypeMismatch "number" notNum


showError :: LispError -> String
showError (NumArgs expected found) 		= "Expected: " ++ show expected ++ "Found: " ++ show found 
showError (BadSpecialForm message form) 	= message ++ ": " ++ show form
showError (NotFunction message function) 	= message ++ ": " ++ show function
showError (UnboundVar message var) 		= message ++ ": " ++ var
showError (Default message) 			= message
showError (Parser parseErr)			= show parseErr

instance Show LispError where show = showError
type ThrowsError = Either LispError

trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val




main :: IO ()
main = do
	args <- getArgs
	evaled <- return $ liftM show $ readExpr (args !! 0) >>= eval
	putStrLn $ extractValue $ trapError evaled



