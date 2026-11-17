import type { Request, Response, NextFunction } from "express";
import { z } from "zod";
import { ApiError } from "../errors/ApiError.js";

export function validateRequest(schema: z.ZodType) {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse(req.body);

    if (!result.success) {
      next(
        new ApiError(
          400,
          "Validation failed",
          "VALIDATION_ERROR",
          result.error.issues,
        ),
      );
    }

    req.body = result.data;
    next();
  };
}
