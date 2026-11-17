export class ApiResponse {
    public readonly success: boolean = true;
    public readonly message: string;
    public readonly data?: unknown;

    constructor(message: string, data?: unknown) {
        this.message = message;
        this.data = data;
    }
}