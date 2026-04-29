import { Test, TestingModule } from '@nestjs/testing';
import { AuthService } from './auth.service';
import { SmsService } from '../sms/sms.service';

describe('AuthService', () => {
  let service: AuthService;

  beforeEach(async () => {
    process.env.SUPABASE_URL = 'https://example.supabase.co';
    process.env.SUPABASE_KEY = 'test-anon-key';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-role-key';

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        AuthService,
        {
          provide: SmsService,
          useValue: {
            sendSms: jest.fn(),
          },
        },
      ],
    }).compile();

    service = module.get<AuthService>(AuthService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
