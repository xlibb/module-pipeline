// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

package io.xlibb.pipeline;

import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.ValueUtils;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;
import org.ballerinalang.langlib.value.EnsureType;

/*
 * Message Context Utility class.
 */
public final class MessageContextUtils {

    private static final BString MESSAGE = StringUtils.fromString("message");
    private static final BString CONTENT = StringUtils.fromString("content");
    private static final BString PROPERTIES = StringUtils.fromString("properties");

    private MessageContextUtils() {}

    public static Object getContentWithType(BObject requestCtx, BTypedesc targetType) {
        BMap<BString, Object> message = requestCtx.getMapValue(MESSAGE);
        Object contentValue = message.getOrThrow(CONTENT);
        return convertWithType(contentValue, targetType);
    }

    public static Object getPropertyWithType(BObject requestCtx, BString key, BTypedesc targetType) {
        BMap<BString, Object> message = requestCtx.getMapValue(MESSAGE);
        BMap properties = message.getMapValue(PROPERTIES);
        Object propertyValue;
        try {
            propertyValue = properties.getOrThrow(key);
        } catch (BError error) {
            return ErrorUtils.createGenericError("Property with key '" + key.getValue() + "' not found", error);
        }
        return convertWithType(propertyValue, targetType);
    }

    private static Object convertWithType(Object value, BTypedesc targetType) {
        // If the value is already of the target type, cast and return it
        Object ensuredValue = EnsureType.ensureType(value, targetType);
        if (ensuredValue instanceof BError) {
            // If the value is not of the target type, convert it using ValueUtils
            try {
                return ValueUtils.convert(value, targetType.getDescribingType());
            } catch (BError error) {
                return ErrorUtils.createGenericError("Failed to convert value to the specified type", error);
            }
        }
        return ensuredValue;
    }
}
