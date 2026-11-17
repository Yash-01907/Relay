export class ApiError extends Error {
    public readonly statusCode: number;
    public readonly errorCode: string;
    public readonly details?: unknown;

    constructor(
        statusCode: number,
        message: string,
        errorCode: string,
        details?: unknown
    ) {
        super(message);

        this.name = "ApiError"; 
        this.statusCode = statusCode;
        this.errorCode = errorCode;
        this.details = details;

        Error.captureStackTrace?.(this, ApiError);
    }
}
