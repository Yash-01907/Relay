import type { Request, Response, NextFunction } from "express";

export const notFound = (req: Request, res: Response, next: NextFunction) => {
  res.status(404).json({
        success: false,
        error: {
            message: "The requested resource was not found.",
            code: "NOT_FOUND"
        }
    });
};
