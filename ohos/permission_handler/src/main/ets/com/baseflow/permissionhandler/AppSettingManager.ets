/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import UIAbility from '@ohos.app.ability.UIAbility';
import bundleManager from '@ohos.bundle.bundleManager';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { ErrorCallback } from './ErrorCallback';
import PermissionConstants from './PermissionConstants';
import Want from '@ohos.app.ability.Want';

export class AppSettingManager {
  openAppSettings(ability: UIAbility | null, successCallback: OpenAppSettingsSuccessCallback, errorCallback: ErrorCallback): void {
    if(ability == null) {
      Log.d(PermissionConstants.LOG_TAG, "Context cannot be null.");
      errorCallback?.onError("PermissionHandler.AppSettingsManager", "Android context cannot be null.");
      return;
    }
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION).then((bundleInfo) => {
      if (bundleInfo == null) {
        successCallback.onSuccess(false);
        return;
      }
      let want: Want = {
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        bundleName: 'com.huawei.hmos.settings',
        uri: 'application_info_entry',
        parameters: {
          pushParams : bundleInfo.name
        }
      };
      try {
        ability.context.startAbility(want).then(() => {
          successCallback.onSuccess(true);
        });
      } catch (error) {
        Log.i(PermissionConstants.LOG_TAG, "start ability exception");
        successCallback?.onSuccess(false);
      }
    });
  }
}

export interface OpenAppSettingsSuccessCallback {
  onSuccess(appSettingsOpenedSuccessfully : boolean): void;
}