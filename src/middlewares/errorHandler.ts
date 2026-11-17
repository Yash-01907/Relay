import type {
  Request,
  Response,
  NextFunction,
  ErrorRequestHandler,
} from "express";
import { ApiError } from "../errors/ApiError.js";

export const errorHandler: ErrorRequestHandler = (
  err: unknown,
  req: Request,
  res: Response,
  next: NextFunction,
) => {
    if(res.headersSent){
        return next(err);
    }
    if(err instanceof ApiError){
       return res.status(err.statusCode).json({
            success: false,
            error: {
                message: err.message,
                code: err.errorCode,
                details: err.details
            }
        })
    }
  console.error(err);


    res.status(500).json({
        success: false,
        error: {
            message: "An unexpected error occurred.",
            code: "INTERNAL_SERVER_ERROR"
        }
    });
};
