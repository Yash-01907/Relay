import type { Request, Response, NextFunction } from "express";

export const notFound = (req : Request, res : Response, next : NextFunction) => {
    res.status(404).json({
        status: "Not Found",
        message: "The requested resource was not found on this server."
    });
}