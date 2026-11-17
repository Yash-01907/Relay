import type { RequestHandler } from "express";
import { ApiError } from "../errors/ApiError.js";

export const notFound: RequestHandler = (req, res, next) => {
  next(new ApiError(404, "The requested resource was not found.", "NOT_FOUND"));
};
