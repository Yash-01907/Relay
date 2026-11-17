import type {
  Request,
  Response,
  NextFunction,
  ErrorRequestHandler,
} from "express";

export const errorHandler: ErrorRequestHandler = (
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
) => {
  console.error(err.stack);
  
    res.status(500).json({
        success: false,
        error: {
            message: "An unexpected error occurred.",
            code: "INTERNAL_SERVER_ERROR"
        }
    });
};
