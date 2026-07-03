import { Request, Response, NextFunction } from 'express';
import { validationResult, ValidationChain } from 'express-validator';
import { ErrorCodes } from '../errors/errorCodes';

/**
 * express-validator 校验链包装器
 * 校验失败自动返回 400 + 统一错误码格式
 *
 * 用法:
 *   router.post('/login', validate([
 *     body('phone').notEmpty().withMessage('手机号不能为空'),
 *   ]), handler);
 */
export function validate(validations: ValidationChain[]) {
  return async (req: Request, res: Response, next: NextFunction) => {
    // 逐个执行校验
    for (const validation of validations) {
      await validation.run(req);
    }

    const errors = validationResult(req);
    if (errors.isEmpty()) {
      return next();
    }

    // 取第一个错误，转换成统一格式
    const first = errors.array()[0];
    const paramInvalid = ErrorCodes.PARAM_INVALID;

    res.status(400).json({
      code: paramInvalid.code,
      message: first.msg,
    });
  };
}
